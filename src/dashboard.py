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

# Default to prod; override with the sidebar if you want to look at dev.
REPO_ROOT = Path(__file__).resolve().parents[1]
WAREHOUSES = {
    "prod": REPO_ROOT / "warehouse" / "prod" / "dog_explorer.duckdb",
    "dev": REPO_ROOT / "warehouse" / "dev" / "dog_explorer.duckdb",
}

# Keeps the size buckets in physical order everywhere they are plotted.
# Alphabetical would render Giant, Large, Medium, Small, Toy - meaningless on an axis.
SIZE_ORDER = ["Toy", "Small", "Medium", "Large", "Giant"]


def size_bar(df: pd.DataFrame, value: str, title: str) -> alt.Chart:
    """Bar chart over size classes, forced into physical order.

    Charting libraries sort categories alphabetically by default, which renders
    Giant, Large, Medium, Small, Toy - the exact ordering mart_size_lifespan
    added size_rank to avoid, and it inverts the trend visually.
    """
    return (
        alt.Chart(df)
        .mark_bar()
        .encode(
            x=alt.X("size_class:N", sort=SIZE_ORDER, title=None),
            y=alt.Y(f"{value}:Q", title=title),
            tooltip=["size_class", value],
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
    size = query(warehouse, "select * from marts.mart_size_lifespan order by size_rank")
    longest = query(warehouse, "select * from marts.mart_longest_lived_breeds order by life_span_rank")
    traits = query(warehouse, "select * from marts.mart_temperament_summary order by breed_count desc")
except (FileNotFoundError, duckdb.Error) as exc:
    st.error(
        f"Could not read the **{warehouse}** warehouse.\n\n`{exc}`\n\n"
        "Build it first:\n\n"
        f"```bash\ncd dog_explorer_dbt\ndbt build --profiles-dir . --target {warehouse}\n```"
    )
    st.stop()

st.caption(
    f"{int(size['breed_count'].sum())} breeds · "
    f"{len(traits)} distinct traits · data from run_date {longest['run_date'].max()}"
)

# --- Question 1 + 2: size distribution and its relationship to life span -----
# Both come from mart_size_lifespan, which is one row per size class.
left, right = st.columns(2)

with left:
    st.subheader("How are breeds distributed across weight classes?")
    st.altair_chart(size_bar(size, "breed_count", "Breeds"), use_container_width=True)

with right:
    st.subheader("Is there a relationship between size and life span?")
    st.altair_chart(
        size_bar(size, "avg_life_span_years", "Average life span (years)"),
        use_container_width=True,
    )
    drop = size["avg_life_span_years"].iloc[0] - size["avg_life_span_years"].iloc[-1]
    st.caption(
        f"Average life span falls {drop:.1f} years from {size['size_class'].iloc[0]} "
        f"to {size['size_class'].iloc[-1]} - bigger breeds live shorter lives."
    )

st.dataframe(
    size[
        [
            "size_class", "breed_count", "pct_of_breeds", "avg_weight_kg",
            "avg_life_span_years", "min_life_span_years", "max_life_span_years",
        ]
    ],
    hide_index=True,
    use_container_width=True,
)

st.divider()

# --- Question 3: longest-lived breeds ---------------------------------------
st.subheader("Which breeds have the longest predicted life span?")

col_a, col_b = st.columns([1, 3])
with col_a:
    top_n = st.slider("Show top", 5, 50, 15, step=5)
    chosen = st.multiselect("Filter by size", SIZE_ORDER, default=[])

shown = longest if not chosen else longest[longest["size_class"].isin(chosen)]
with col_b:
    st.dataframe(
        shown.head(top_n)[
            ["life_span_rank", "breed_name", "breed_group", "size_class",
             "life_span_avg_years", "life_span_min_years", "life_span_max_years"]
        ],
        hide_index=True,
        use_container_width=True,
    )
st.caption(
    "Ranked on the midpoint of the published range, not the maximum: ranking on the "
    "maximum rewards a breed with a wide, uncertain range over one with a tight, high "
    "one. Ties share a rank."
)

st.divider()

# --- Question 4: temperaments among family-friendly breeds ------------------
st.subheader("What are the top temperaments among family-friendly breeds?")

hide_defining = st.checkbox(
    "Hide the traits used to define 'family-friendly'",
    value=False,
    help=(
        "Those traits are circular by construction: a breed is in this population "
        "because it has one of them, so their high counts are guaranteed rather than "
        "discovered."
    ),
)
shown_traits = traits[~traits["is_defining_trait"]] if hide_defining else traits

st.altair_chart(
    alt.Chart(shown_traits.head(15))
    .mark_bar()
    .encode(
        # sort='-y' keeps the bars in descending count order rather than
        # alphabetical, so the ranking is readable straight off the axis.
        x=alt.X("trait:N", sort="-y", title=None),
        y=alt.Y("breed_count:Q", title="Breeds"),
        color=alt.Color(
            "is_defining_trait:N",
            title="Used to define family-friendly",
            scale=alt.Scale(scheme="tableau10"),
        ),
        tooltip=["trait", "breed_count", "pct_of_family_friendly_breeds", "is_defining_trait"],
    ),
    use_container_width=True,
)
st.dataframe(
    shown_traits[["trait", "breed_count", "pct_of_family_friendly_breeds", "is_defining_trait"]],
    hide_index=True,
    use_container_width=True,
)
st.caption(
    "'Family-friendly' has no flag in the source, so it is defined as a short, editable "
    "list of traits in mart_temperament_summary.sql. Rows flagged as defining traits "
    "helped select this population, so their counts are circular; the unflagged ones are "
    "genuine patterns."
)
