# Functional Programming

- NEVER use classes when a plain function or module of functions will do. If a framework requires a class, keep it as a thin wrapper and extract all logic into pure functions.
- NEVER use mutable state. Prefer `const`, `readonly`, frozen objects, and immutable data structures.
- NEVER use inheritance. Use composition and higher-order functions instead.
- NEVER write methods with side effects without isolating them at the boundary. Keep core logic as pure functions.
- NEVER use imperative loops (`for`, `while`) when a declarative alternative exists (`map`, `filter`, `reduce`, `flatMap`, etc.).
