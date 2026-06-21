---
name: testing
description: Complete guide for Python testing including pytest, fixtures, mocking, parametrization, coverage, ML model testing, API testing, and CI integration. Use when writing unit tests, integration tests, or setting up test infrastructure.
paths:
  - "**/tests/**"
  - "**/test_*.py"
  - "**/*_test.py"
---

# Testing

## Stack 2025

| Component | Tools |
|-----------|-------|
| Framework | pytest, unittest |
| Mocking | pytest-mock, unittest.mock, responses |
| Coverage | pytest-cov, coverage.py |
| API Testing | httpx, pytest-asyncio, respx |
| ML Testing | pytest, great_expectations, deepchecks |
| Property-Based | hypothesis |
| Fixtures | pytest-fixtures, factory_boy, faker |
| Performance | pytest-benchmark, locust |

---

## pytest Basics

### Project Structure

```
project/
├── src/
│   └── myapp/
│       ├── __init__.py
│       ├── models.py
│       └── services.py
├── tests/
│   ├── __init__.py
│   ├── conftest.py          # Shared fixtures
│   ├── unit/
│   │   ├── test_models.py
│   │   └── test_services.py
│   ├── integration/
│   │   └── test_api.py
│   └── e2e/
│       └── test_workflows.py
├── pyproject.toml
└── pytest.ini
```

### Configuration

```ini
# pytest.ini
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
python_classes = Test*
addopts = -v --tb=short --strict-markers
markers =
    slow: marks tests as slow
    integration: integration tests
    gpu: requires GPU
filterwarnings =
    ignore::DeprecationWarning
```

```toml
# pyproject.toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v --tb=short -x --strict-markers"
markers = [
    "slow: marks tests as slow",
    "integration: integration tests",
]

[tool.coverage.run]
source = ["src"]
omit = ["tests/*", "*/__init__.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
]
```

### Running Tests

```bash
# Run all tests
pytest

# Verbose with print output
pytest -v -s

# Specific file/test
pytest tests/test_models.py
pytest tests/test_models.py::test_user_creation
pytest tests/test_models.py::TestUser::test_name

# By marker
pytest -m "not slow"
pytest -m "integration"

# By keyword
pytest -k "user and not delete"

# Stop on first failure
pytest -x

# Run last failed
pytest --lf

# Parallel (pytest-xdist)
pytest -n auto
pytest -n 4

# Coverage
pytest --cov=src --cov-report=html --cov-report=term-missing
```

---

## Writing Tests

### Basic Test

```python
# tests/test_calculator.py
from myapp.calculator import add, divide

def test_add():
    assert add(2, 3) == 5

def test_add_negative():
    assert add(-1, 1) == 0

def test_divide():
    assert divide(10, 2) == 5.0

def test_divide_by_zero():
    import pytest
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)

def test_divide_by_zero_message():
    import pytest
    with pytest.raises(ZeroDivisionError, match="division by zero"):
        divide(10, 0)
```

### Test Classes

```python
class TestUser:
    """Group related tests."""
    
    def test_create_user(self):
        user = User(name="John", email="john@example.com")
        assert user.name == "John"
    
    def test_user_full_name(self):
        user = User(name="John", last_name="Doe")
        assert user.full_name == "John Doe"
    
    def test_user_invalid_email(self):
        with pytest.raises(ValueError, match="Invalid email"):
            User(name="John", email="invalid")
```

### Parametrization

```python
import pytest

# Simple parametrize
@pytest.mark.parametrize("input,expected", [
    (1, 2),
    (2, 4),
    (3, 6),
    (0, 0),
    (-1, -2),
])
def test_double(input, expected):
    assert double(input) == expected

# Multiple parameters
@pytest.mark.parametrize("a,b,expected", [
    (1, 2, 3),
    (0, 0, 0),
    (-1, 1, 0),
    (100, 200, 300),
])
def test_add(a, b, expected):
    assert add(a, b) == expected

# IDs for clarity
@pytest.mark.parametrize("email,valid", [
    ("user@example.com", True),
    ("user@domain.co.uk", True),
    ("invalid", False),
    ("@nodomain.com", False),
    ("spaces in@email.com", False),
], ids=["valid_simple", "valid_subdomain", "no_at", "no_local", "spaces"])
def test_email_validation(email, valid):
    assert is_valid_email(email) == valid

# Combine parametrize decorators (cartesian product)
@pytest.mark.parametrize("x", [1, 2])
@pytest.mark.parametrize("y", [10, 20])
def test_multiply(x, y):
    # Runs 4 times: (1,10), (1,20), (2,10), (2,20)
    assert multiply(x, y) == x * y
```

### Markers

```python
import pytest

@pytest.mark.slow
def test_large_dataset():
    """Takes a long time."""
    process_million_records()

@pytest.mark.integration
def test_database_connection():
    """Requires database."""
    db.connect()

@pytest.mark.skip(reason="Not implemented yet")
def test_future_feature():
    pass

@pytest.mark.skipif(sys.platform == "win32", reason="Unix only")
def test_unix_permissions():
    pass

@pytest.mark.xfail(reason="Known bug #123")
def test_known_issue():
    buggy_function()

@pytest.mark.gpu
@pytest.mark.skipif(not torch.cuda.is_available(), reason="No GPU")
def test_gpu_training():
    model.to("cuda")
```

---

## Fixtures

### Basic Fixtures

```python
# conftest.py
import pytest

@pytest.fixture
def user():
    """Create a test user."""
    return User(name="Test", email="test@example.com")

@pytest.fixture
def admin_user():
    """Create an admin user."""
    return User(name="Admin", email="admin@example.com", role="admin")

# Using fixtures
def test_user_name(user):
    assert user.name == "Test"

def test_admin_permissions(admin_user):
    assert admin_user.can_delete_users()
```

### Fixture Scopes

```python
@pytest.fixture(scope="function")  # Default: new for each test
def db_session():
    session = create_session()
    yield session
    session.rollback()
    session.close()

@pytest.fixture(scope="class")  # Once per test class
def api_client():
    client = APIClient()
    client.authenticate()
    yield client
    client.logout()

@pytest.fixture(scope="module")  # Once per module
def database():
    db = Database()
    db.create_tables()
    yield db
    db.drop_tables()

@pytest.fixture(scope="session")  # Once per test session
def docker_services():
    compose = DockerCompose()
    compose.start()
    yield compose
    compose.stop()
```

### Fixture Dependencies

```python
@pytest.fixture
def db():
    return Database()

@pytest.fixture
def user_repo(db):
    return UserRepository(db)

@pytest.fixture
def user_service(user_repo):
    return UserService(user_repo)

def test_create_user(user_service):
    user = user_service.create("John", "john@example.com")
    assert user.id is not None
```

### Factory Fixtures

```python
@pytest.fixture
def make_user():
    """Factory fixture for creating users."""
    created_users = []
    
    def _make_user(name="Test", email=None, **kwargs):
        email = email or f"{name.lower()}@example.com"
        user = User(name=name, email=email, **kwargs)
        created_users.append(user)
        return user
    
    yield _make_user
    
    # Cleanup
    for user in created_users:
        user.delete()

def test_multiple_users(make_user):
    user1 = make_user("Alice")
    user2 = make_user("Bob", role="admin")
    assert user1.email == "alice@example.com"
    assert user2.role == "admin"
```

### Fixtures with Faker

```python
import pytest
from faker import Faker

fake = Faker()

@pytest.fixture
def random_user():
    return User(
        name=fake.name(),
        email=fake.email(),
        address=fake.address(),
    )

@pytest.fixture
def random_users():
    def _generate(count=10):
        return [
            User(name=fake.name(), email=fake.email())
            for _ in range(count)
        ]
    return _generate
```

---

## Mocking

### pytest-mock

```python
def test_send_email(mocker):
    # Mock the send function
    mock_send = mocker.patch("myapp.email.send_email")
    mock_send.return_value = True
    
    result = notify_user("user@example.com", "Hello")
    
    assert result is True
    mock_send.assert_called_once_with("user@example.com", "Hello")

def test_api_call(mocker):
    # Mock external API
    mock_response = mocker.Mock()
    mock_response.json.return_value = {"status": "ok"}
    mock_response.status_code = 200
    
    mocker.patch("requests.get", return_value=mock_response)
    
    result = fetch_data("https://api.example.com")
    assert result["status"] == "ok"

def test_database_error(mocker):
    # Mock to raise exception
    mocker.patch(
        "myapp.db.query",
        side_effect=DatabaseError("Connection failed")
    )
    
    with pytest.raises(DatabaseError):
        get_users()
```

### unittest.mock

```python
from unittest.mock import Mock, patch, MagicMock

def test_with_patch():
    with patch("myapp.external.api_call") as mock_api:
        mock_api.return_value = {"data": "test"}
        result = process_data()
        assert result == "test"

@patch("myapp.services.send_notification")
def test_notification(mock_send):
    mock_send.return_value = True
    
    user = User(name="Test")
    user.save()
    
    mock_send.assert_called_once()

def test_mock_object():
    mock_db = Mock()
    mock_db.query.return_value = [{"id": 1, "name": "Test"}]
    
    service = UserService(db=mock_db)
    users = service.get_all()
    
    assert len(users) == 1
    mock_db.query.assert_called_with("SELECT * FROM users")

def test_mock_context_manager():
    mock_file = MagicMock()
    mock_file.__enter__.return_value.read.return_value = "file content"
    
    with patch("builtins.open", return_value=mock_file):
        content = read_config("config.json")
        assert content == "file content"
```

### Mocking HTTP (responses)

```python
import responses
import requests

@responses.activate
def test_api_request():
    # Mock the endpoint
    responses.add(
        responses.GET,
        "https://api.example.com/users",
        json={"users": [{"id": 1, "name": "John"}]},
        status=200,
    )
    
    result = fetch_users()
    
    assert len(result["users"]) == 1
    assert responses.calls[0].request.url == "https://api.example.com/users"

@responses.activate
def test_api_error():
    responses.add(
        responses.GET,
        "https://api.example.com/users",
        json={"error": "Not found"},
        status=404,
    )
    
    with pytest.raises(APIError):
        fetch_users()
```

### Mocking Async (respx)

```python
import httpx
import respx
import pytest

@pytest.mark.asyncio
@respx.mock
async def test_async_api():
    respx.get("https://api.example.com/data").mock(
        return_value=httpx.Response(200, json={"result": "ok"})
    )
    
    async with httpx.AsyncClient() as client:
        response = await client.get("https://api.example.com/data")
    
    assert response.json()["result"] == "ok"
```

---

## Async Testing

```python
import pytest
import asyncio

@pytest.mark.asyncio
async def test_async_function():
    result = await async_fetch_data()
    assert result is not None

@pytest.mark.asyncio
async def test_multiple_async():
    results = await asyncio.gather(
        async_task_1(),
        async_task_2(),
        async_task_3(),
    )
    assert len(results) == 3

# Async fixture
@pytest.fixture
async def async_client():
    client = AsyncClient()
    await client.connect()
    yield client
    await client.disconnect()

@pytest.mark.asyncio
async def test_with_async_fixture(async_client):
    result = await async_client.fetch("/api/data")
    assert result.status == 200
```

---

## API Testing

### FastAPI Testing

```python
from fastapi.testclient import TestClient
from myapp.main import app

client = TestClient(app)

def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "Hello"}

def test_create_user():
    response = client.post(
        "/users",
        json={"name": "John", "email": "john@example.com"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "John"
    assert "id" in data

def test_auth_required():
    response = client.get("/protected")
    assert response.status_code == 401

def test_with_auth():
    response = client.get(
        "/protected",
        headers={"Authorization": "Bearer test-token"},
    )
    assert response.status_code == 200

# Async testing
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_async_endpoint():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/async-endpoint")
    assert response.status_code == 200
```

### Fixtures for API Testing

```python
# conftest.py
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from myapp.main import app
from myapp.database import get_db, Base

@pytest.fixture(scope="session")
def engine():
    return create_engine("sqlite:///./test.db")

@pytest.fixture(scope="session")
def tables(engine):
    Base.metadata.create_all(engine)
    yield
    Base.metadata.drop_all(engine)

@pytest.fixture
def db_session(engine, tables):
    connection = engine.connect()
    transaction = connection.begin()
    Session = sessionmaker(bind=connection)
    session = Session()
    
    yield session
    
    session.close()
    transaction.rollback()
    connection.close()

@pytest.fixture
def client(db_session):
    def override_get_db():
        yield db_session
    
    app.dependency_overrides[get_db] = override_get_db
    
    with TestClient(app) as client:
        yield client
    
    app.dependency_overrides.clear()
```

---

## ML Model Testing

### Data Validation

```python
import pytest
import pandas as pd
import numpy as np

def test_training_data_schema():
    df = load_training_data()
    
    # Required columns
    required_columns = ["feature1", "feature2", "target"]
    assert all(col in df.columns for col in required_columns)
    
    # Data types
    assert df["feature1"].dtype == np.float64
    assert df["target"].dtype in [np.int64, np.int32]
    
    # No nulls in critical columns
    assert df["target"].isna().sum() == 0
    
    # Value ranges
    assert df["feature1"].between(0, 1).all()

def test_no_data_leakage():
    X_train, X_test, y_train, y_test = load_split_data()
    
    # Check no overlap
    train_indices = set(X_train.index)
    test_indices = set(X_test.index)
    assert train_indices.isdisjoint(test_indices)

def test_class_balance():
    y = load_labels()
    class_counts = pd.Series(y).value_counts(normalize=True)
    
    # No class should be less than 10%
    assert class_counts.min() >= 0.10
```

### Model Performance

```python
import pytest
from sklearn.metrics import accuracy_score, f1_score

@pytest.fixture(scope="module")
def trained_model():
    model = load_model("model.pkl")
    return model

@pytest.fixture(scope="module")
def test_data():
    X_test, y_test = load_test_data()
    return X_test, y_test

def test_model_accuracy(trained_model, test_data):
    X_test, y_test = test_data
    y_pred = trained_model.predict(X_test)
    
    accuracy = accuracy_score(y_test, y_pred)
    assert accuracy >= 0.85, f"Accuracy {accuracy} below threshold"

def test_model_f1(trained_model, test_data):
    X_test, y_test = test_data
    y_pred = trained_model.predict(X_test)
    
    f1 = f1_score(y_test, y_pred, average="weighted")
    assert f1 >= 0.80

def test_model_inference_time(trained_model, test_data):
    import time
    X_test, _ = test_data
    
    start = time.time()
    trained_model.predict(X_test[:100])
    elapsed = time.time() - start
    
    # Should predict 100 samples in under 1 second
    assert elapsed < 1.0

def test_model_deterministic(trained_model, test_data):
    X_test, _ = test_data
    sample = X_test[:10]
    
    pred1 = trained_model.predict(sample)
    pred2 = trained_model.predict(sample)
    
    assert np.array_equal(pred1, pred2)
```

### Model Robustness

```python
def test_model_handles_missing_values(trained_model):
    X_with_nan = np.array([[1.0, np.nan, 3.0]])
    
    # Should not raise error
    try:
        pred = trained_model.predict(X_with_nan)
    except Exception as e:
        pytest.fail(f"Model failed on NaN input: {e}")

def test_model_handles_edge_cases(trained_model):
    edge_cases = [
        np.zeros((1, 10)),           # All zeros
        np.ones((1, 10)),            # All ones
        np.full((1, 10), -999),      # Extreme negative
        np.full((1, 10), 999),       # Extreme positive
    ]
    
    for case in edge_cases:
        pred = trained_model.predict(case)
        assert pred is not None
        assert not np.isnan(pred).any()

def test_model_probability_sum(trained_model, test_data):
    X_test, _ = test_data
    
    if hasattr(trained_model, "predict_proba"):
        probs = trained_model.predict_proba(X_test)
        sums = probs.sum(axis=1)
        
        assert np.allclose(sums, 1.0, atol=1e-6)
```

### Regression Testing

```python
import json
import pytest

@pytest.fixture(scope="module")
def baseline_metrics():
    with open("baseline_metrics.json") as f:
        return json.load(f)

def test_no_regression(trained_model, test_data, baseline_metrics):
    X_test, y_test = test_data
    y_pred = trained_model.predict(X_test)
    
    current_accuracy = accuracy_score(y_test, y_pred)
    baseline_accuracy = baseline_metrics["accuracy"]
    
    # Allow 2% degradation
    assert current_accuracy >= baseline_accuracy - 0.02, \
        f"Regression: {current_accuracy:.4f} < {baseline_accuracy:.4f} - 0.02"

def test_prediction_consistency():
    """Test that predictions match expected for known inputs."""
    model = load_model()
    
    # Known input-output pairs
    test_cases = [
        (np.array([[1.0, 2.0, 3.0]]), 0),
        (np.array([[4.0, 5.0, 6.0]]), 1),
    ]
    
    for input_data, expected in test_cases:
        pred = model.predict(input_data)[0]
        assert pred == expected, f"Expected {expected}, got {pred}"
```

---

## Property-Based Testing (Hypothesis)

```python
from hypothesis import given, strategies as st, settings

@given(st.integers(), st.integers())
def test_add_commutative(a, b):
    assert add(a, b) == add(b, a)

@given(st.lists(st.integers()))
def test_sort_length_preserved(lst):
    sorted_lst = sorted(lst)
    assert len(sorted_lst) == len(lst)

@given(st.text(min_size=1))
def test_reverse_twice_is_identity(s):
    assert s[::-1][::-1] == s

@given(
    st.floats(min_value=-1e6, max_value=1e6, allow_nan=False),
    st.floats(min_value=-1e6, max_value=1e6, allow_nan=False),
)
def test_multiply_signs(a, b):
    result = a * b
    if a > 0 and b > 0:
        assert result > 0
    elif a < 0 and b < 0:
        assert result > 0

# Custom strategies
user_strategy = st.fixed_dictionaries({
    "name": st.text(min_size=1, max_size=50),
    "email": st.emails(),
    "age": st.integers(min_value=0, max_value=150),
})

@given(user_strategy)
@settings(max_examples=100)
def test_user_creation(user_data):
    user = User(**user_data)
    assert user.name == user_data["name"]
```

---

## Coverage

### Commands

```bash
# Run with coverage
pytest --cov=src --cov-report=term-missing

# HTML report
pytest --cov=src --cov-report=html
open htmlcov/index.html

# XML for CI
pytest --cov=src --cov-report=xml

# Fail under threshold
pytest --cov=src --cov-fail-under=80

# Branch coverage
pytest --cov=src --cov-branch
```

### Exclude from Coverage

```python
# Exclude specific lines
if TYPE_CHECKING:  # pragma: no cover
    from typing import Optional

def debug_only():  # pragma: no cover
    print("Debug info")

# Exclude blocks
if __name__ == "__main__":  # pragma: no cover
    main()
```

---

## CI Integration

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      
      - name: Install dependencies
        run: |
          pip install -e ".[test]"
      
      - name: Run tests
        run: |
          pytest --cov=src --cov-report=xml -v
      
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: coverage.xml
          fail_ci_if_error: true
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Test implementation details | Test behavior/interface |
| Hardcode test data paths | Use fixtures, relative paths |
| Skip cleanup in fixtures | Use yield + cleanup |
| Mock everything | Mock external dependencies only |
| Write flaky tests | Ensure deterministic tests |
| Ignore test failures | Fix or mark as xfail with reason |
| One giant test | Small, focused tests |
| Test private methods | Test public API |
