# Backend Definition Flow (`/api/cities`)

## 1. Purpose
This document explains the implementation flow used to define a clean backend endpoint for cities in RoTransit.  
The goal is to expose `GET /api/cities` using a clear layering approach: entity -> repository -> service -> controller.

## 2. Target endpoint
- Method: `GET`
- Path: `/api/cities`
- Response type: JSON array of city DTOs
- Expected fields per item: `id`, `name`, `country`

## 3. Implementation flow

### Step 1: Define the JPA entity (`City`)
- Create a `City` entity mapped to the `cities` table.
- Define columns and primary key (`id`).
- This class represents how city records are stored in PostgreSQL.

Why this matters:
- It gives Spring Data JPA the database mapping needed for CRUD/read queries.

### Step 2: Create repository (`CityRepository`)
- Add a repository interface extending `JpaRepository<City, Long>`.
- Define `findAllByOrderByCountryAscNameAsc()`.

Why this matters:
- Sorting at query level guarantees stable ordering (`country`, then `name`) for API consumers and tests.

### Step 3: Define response DTO (`CityResponse`)
- Create a DTO used by the API response with only:
  - `id`
  - `name`
  - `country`

Why this matters:
- Controllers return DTOs, not entities, to avoid leaking persistence details.

### Step 4: Add service layer (`CityService`)
- Read city entities through `CityRepository`.
- Map each entity to `CityResponse`.
- Keep transformation and business logic here.

Why this matters:
- Service keeps controller thin and centralizes domain logic.

### Step 5: Expose controller (`CityController`)
- Add REST controller endpoint `GET /api/cities`.
- Delegate to `CityService`.
- Return list of `CityResponse`.

Why this matters:
- Controller handles HTTP concerns only (route, status, serialization).

### Step 6: Seed minimal data
- Insert 1-2 records (example: Brasov) in the database init script.
- Ensure endpoint returns real data immediately in dev/test.

Why this matters:
- Speeds up validation and avoids empty responses during early integration.

### Step 7: Add integration test
- Add one integration test for `GET /api/cities`.
- Validate:
  - HTTP status is OK
  - response contains expected items
  - order is stable

Why this matters:
- Confirms full stack behavior (controller + service + repository + DB).

## 4. Clean architecture guidelines
- Return DTOs only from controllers (never JPA entities).
- Keep controller thin; keep business logic in service.
- Apply sorting in repository for deterministic API output.
- Add a global error format early using `@ControllerAdvice`.

## 5. Suggested package layout
- `controller` -> `CityController`
- `service` -> `CityService`
- `repository` -> `CityRepository`
- `model` -> `City`
- `dto` -> `CityResponse`

## 6. Result
Following this flow provides:
- predictable API behavior
- clean separation of concerns
- easier testing and maintenance
- safer API contracts for frontend integration
