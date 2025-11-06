# Master 2 Internship Proposal

## Title: Migration of an OCaml Codebase from Lwt to Eio (Effect-Based Concurrency)

### Context

The `coqbot` project maintains a significant OCaml codebase that relies on the **Lwt** library for all asynchronous operations, including inter-process communication, network requests, file I/O, and other concurrent task management.

With the release of **OCaml 5**, a new concurrency model based on _effect handlers_ has been introduced. This model enables direct-style, non-monadic concurrent programming through the **Eio** library. Migrating from Lwt to Eio potentially affect most of the system's components and requires careful redesign of asynchronous mechanisms.

### Internship Objective

The objective of this internship is to design and implement a gradual migration of an existing OCaml codebase from Lwt to Eio, while maintaining functional integrity and performance.

The project will give the student hands-on experience with OCaml 5's new concurrency model, modern systems programming, and contribute to the modernization of a real-world software system.

### Proposed Work Plan

1.  **Development Environment Setup:** Configure an OCaml 5 development environment and an automated test suite.
2.  **Concurrency Model Analysis:** Compare Lwt and Eio models and define migration strategies.
3.  **Progressive Module Migration:** Iteratively migrate modules:
    - **Process Management:** (`Lwt_process` -> `Eio.Process`)
    - **File I/O:** (`Lwt_io` -> `Eio.Flow` for file operations, temp files, stdout/stderr)
    - **Unix operations:** (`Lwt_unix` -> `Eio.Unix` for system calls and sleep)
    - **HTTP client and server:** (`Cohttp_lwt`/`Cohttp_lwt_unix` -> `Piaf`/`Cohttp_eio`)
    - **Streams:** (`Lwt_stream` -> `Eio.Stream`)
    - **Preemptive threading:** (`Lwt_preemptive` -> Eio's fiber model)
    - **Event loop:** (`Lwt_main.run` -> Eio's event loop)
    - **List operations:** (`Lwt_list` -> Eio's concurrent list operations)
    - **Result monad:** (`Lwt_result` -> Eio's error handling)
    - **Async operations:** (`Lwt.async` -> Eio's fiber spawning)
4.  **Logging and Error Handling:** Update systems to fit Eio's concurrency model.
5.  **Validation and Performance Testing:** Ensure stability and benchmark performance.
6.  **Documentation and Finalization:** Document all migration steps, and solutions; remove all Lwt dependencies.

### Supervision and Expected Skills

**Required skills:** Solid knowledge of OCaml and functional programming. Familiarity with concurrency or asynchronous programming is a plus.

### Expected Outcomes

- A stable, production-ready OCaml codebase fully migrated to Eio.
- A detailed technical report describing the migration process, challenges, and performance evaluation.

### Duration

5 to 6 months

### Start Date

### Location
