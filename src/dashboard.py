"""Streamlit dashboard over the dog_explorer marts.

Reads the DuckDB warehouse directly - the marts are already shaped one question
per model, so nothing is transformed here. Anything that looks like business
logic belongs in dbt, not in the presentation layer.

Run with:
    streamlit run src/dashboard.py
"""

from pathlib import Path

import altair as alt
import duckdb
import pandas as pd
import streamlit as st

# Default to dev; override with the sidebar if you want to look at prod.
# dev is dbt's own default target, so this is the warehouse that exists after a
# plain `dbt build` - the dashboard opens against whatever a fresh clone built,
# rather than erroring on a prod file nobody asked for.
REPO_ROOT = Path(__file__).resolve().parents[1]
WAREHOUSES = {
    "dev": REPO_ROOT / "warehouse" / "dev" / "dog_explorer.duckdb",
    "prod": REPO_ROOT / "warehouse" / "prod" / "dog_explorer.duckdb",
}

# Keeps the weight bands in physical order everywhere they are plotted.
# Alphabetical would render Giant, Large, Medium, Small, Toy - meaningless on
# an axis. Weight is the only banded measure in the warehouse; height is used
# raw, so it never appears here.
BAND_ORDER = ["Toy", "Small", "Medium", "Large", "Giant"]


def weight_bar(df: pd.DataFrame, value: str, title: str) -> alt.Chart:
    """Bar chart over the weight classes, forced into physical order.

    Charting libraries sort categories alphabetically by default, which renders
    Giant, Large, Medium, Small, Toy - the exact ordering mart_weight_distribution
    added weight_rank to avoid.
    """
    return (
        alt.Chart(df)
        .mark_bar()
        .encode(
            x=alt.X("weight_class:N", sort=BAND_ORDER, title=None),
            y=alt.Y(f"{value}:Q", title=title),
            tooltip=["weight_class", value],
        )
    )


@st.cache_data
def query(warehouse: str, sql: str) -> pd.DataFrame:
    """Run a read-only query. read_only so the dashboard never locks the file
    that dbt needs to write - DuckDB allows only one writing process."""
    path = WAREHOUSES[warehouse]
    if not path.exists():
        raise FileNotFoundError(path)
    with duckdb.connect(str(path), read_only=True) as con:
        return con.sql(sql).df()


st.set_page_config(page_title="Dog Breed Explorer", page_icon="🐕", layout="wide")
st.title("🐕 Dog Breed Explorer")

warehouse = st.sidebar.radio("Warehouse", list(WAREHOUSES), help="Which dbt target to read.")

try:
    weights = query(warehouse, "select * from marts.mart_weight_distribution order by weight_rank")
    scatter = query(warehouse, "select * from marts.mart_height_lifespan_scatter")
    corr = query(warehouse, "select * from marts.mart_height_lifespan_correlation")
    longest = query(warehouse, "select * from marts.mart_longest_lived_breeds order by life_span_rank")
except (FileNotFoundError, duckdb.Error) as exc:
    st.error(
        f"Could not read the **{warehouse}** warehouse.\n\n`{exc}`\n\n"
        "Build it first:\n\n"
        f"```bash\ncd dog_explorer_dbt\ndbt build --profiles-dir . --target {warehouse}\n```"
    )
    st.stop()

st.caption(
    f"{int(weights['breed_count'].sum())} breeds · "
    f"data from run_date {longest['run_date'].max()}"
)

# --- Question 1: weight distribution ----------------------------------------
# mart_weight_distribution, one row per weight class. Weight, not height: this
# question names weight classes explicitly.
st.subheader("How are breeds distributed across weight classes?")
st.altair_chart(weight_bar(weights, "breed_count", "Breeds"), use_container_width=True)

st.divider()

# --- Question 2: size (height) vs life span ---------------------------------
# The scatter plots mart_height_lifespan_scatter (one row per breed); the
# coefficient beside it comes from mart_height_lifespan_correlation, computed
# over those same rows. Size means HEIGHT - the weight bands above answer a
# different question and are not a stand-in for this one.
st.subheader("Is there a relationship between size and life span?")

r = corr.iloc[0]

st.metric(
    "Pearson correlation, height vs life span",
    f"{r['pearson_r']:+.3f}",
    help=f"Computed over the {int(r['n_breeds'])} breeds publishing both a height and a life span.",
)

points = (
    alt.Chart(scatter)
    .mark_circle(size=45, opacity=0.45)
    .encode(
        x=alt.X("height_avg_cm:Q", title="Average height (cm)", scale=alt.Scale(zero=False)),
        y=alt.Y("life_span_avg_years:Q", title="Life span (years)", scale=alt.Scale(zero=False)),
        tooltip=["breed_name", "height_avg_cm", "life_span_avg_years"],
    )
)
st.altair_chart(
    # The fitted line is the correlation made visible - same data, same slope.
    points + points.transform_regression("height_avg_cm", "life_span_avg_years").mark_line(color="firebrick"),
    use_container_width=True,
)
st.caption(
    f"One point per breed, {int(r['n_breeds'])} of them - raw height against raw life span, "
    f"never bucketed. Pearson r = {r['pearson_r']:+.3f}: taller breeds live shorter lives, "
    "with plenty of scatter around the trend."
)

st.divider()

# --- Question 3: longest-lived breeds ---------------------------------------
# Rank 1 only. The mart ranks with RANK(), so ties share rank 1 and every
# joint-longest-lived breed appears - there is nothing to slice or page through.
st.subheader("Which breeds have the longest predicted life span?")

st.dataframe(
    longest[longest["life_span_rank"] == 1][
        ["breed_name", "breed_group", "life_span_avg_years"]
    ],
    hide_index=True,
    use_container_width=True,
)
