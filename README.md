# Landa OS

Landa OS is a Nigerian prop-tech platform focused on secure, fraud-free rentals. This is the Lean MVP build.

## Architecture
- **Pattern:** Feature-First MVCS (Model-View-Controller-Service)
- **State Management:** Provider
- **Mock Data Strategy:** All services use the Repository Pattern. We currently use `Mock` services that simulate network latency (2 seconds) and return hardcoded, realistic dummy data. Controllers depend *only* on abstract interfaces.

## Folder Structure
```text
/lib
  /core         (themes, constants, routing, generic widgets)
  /features
    /auth       (models, views, controllers, services)
    /agreements
    /payments
    /dashboard
```

## Theme Colors
- **Primary (Deep Navy):** `#0A192F`
- **Secondary (Emerald Green):** `#10B981`
- **Action (Electric Blue):** `#3B82F6`
- **Warning (Amber):** `#F59E0B`
- **Background (Soft Grey):** `#F8FAFC`
