# Stack pack

- **Id:** python
- **Service skill:** implement-python-service
- **Rules:** python-backend.mdc, vapt-python.mdc
- **Skills:** implement-python-service, implement-python-bff, scaffold-python-service
- **Data stores:** PostgreSQL 15
- **Backend:** Python 3.13, FastAPI, Pydantic v2
- **HTTP:** FastAPI APIRouter
- **Security:** FastAPI security dependencies
- **Database:** PostgreSQL 15, SQLAlchemy 2, Alembic
- **Tests:** pytest
- **Local run:** Compose API :8080, UI :8081, postgres:15-alpine
- **Backend verify:** python -m pytest --junitxml=pytest-report.xml --cov --cov-report=xml:coverage.xml
- **Backend verify (fast):** python -m pytest -q
- **Coverage:** coverage.xml
- **Tests report:** pytest-report.xml
- **Auth:** a security Depends() or an explicit public dependency on every route
- **Quality snippet:** python/pytest.ini
- **Dockerfile:** docker/Dockerfile.python

A new service uses FastAPI. Django stays only when the repo already uses it. Do not add `pom.xml` or a Node service framework. React 19, TypeScript 5.9, and Vite 7 stay the UI.
