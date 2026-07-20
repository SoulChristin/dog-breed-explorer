# Dog Breed Explorer

An analytics pipeline over [TheDogAPI](https://api.thedogapi.com/v1/breeds).

See **(DECISIONS.md)** for the reasoning and trade-offs behind of some of the choices.


Phase 1: **Extraction & Ingestion** 

`src/ingest_breeds.py` — fetches the breed catalogue from TheDogAPI and writes the raw response to disk, unmodified.


## Running it

```bash
pip install -r requirements.txt
export DOG_API_KEY='.........'  ##The key was locally stored
python src/ingest_breeds.py