# Agent Context for Landa OS

## Project Overview
Landa OS is a Nigerian prop-tech platform focused on secure, fraud-free rentals.

## Core Rules & Constraints
1. **Architecture & State Management:**
   - Strictly modular, "Feature-First" MVCS architecture.
   - Use `provider` for state management and DI.
   - Do NOT organize by file types globally; organize by feature (e.g., `lib/features/auth/models`).

2. **The Mock Data Strategy:**
   - Implement the Repository Pattern.
   - Create abstract interface classes for all services (`I[Feature]Service`).
   - Create mock implementations returning realistic dummy data after a 2-second `Future.delayed`.
   - Controllers must depend *only* on abstract interfaces. This ensures zero UI/Controller changes when swapping to real APIs (Supabase/SmileID/Paystack) later.

3. **Theme & UI Guidelines:**
   - **Primary:** `#0A192F` (Scaffold backgrounds in Landlord mode, AppBars, primary text, primary buttons).
   - **Secondary:** `#10B981` (Success states, "PAID" pills, "Pay Rent", financial progress).
   - **Action:** `#3B82F6` (Active links, "Sign Agreement" CTAs).
   - **Warning:** `#F59E0B` (48-hour Escrow timers, pending states).
   - **Background:** `#F8FAFC` (Scaffold backgrounds in Tenant mobile view).

4. **Coding Standards:**
   - Meticulously comment every class, complex method, and UI feature. Explain *why*.
   - Keep `build` methods small. Extract UI components into private methods or separate stateless widgets.
   - Avoid duplicating logic. Understand the codebase context before generating new code.
