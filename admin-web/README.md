# Oasis Staff Portal

A standalone React, TypeScript and Vite staff portal for short-stay operations.

## Local preview

```sh
cd admin-web
npm install
npm run dev
```

The local preview opens a demo sign-in and uses clearly labeled fixture records. Actions only update in-memory sample data; they do not call a payment provider or change a backend record.

Production staff authentication and live API integration are intentionally not wired until the backend team provides the staff identity, permissions, admin data, action and audit contracts. The screens consume a typed `AdminRepository` boundary so the fixture implementation can be replaced without changing the presentation layer.
