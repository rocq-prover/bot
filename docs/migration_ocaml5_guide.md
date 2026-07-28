# Internship guide - migration to OCaml 5

## Objective
The goal of this project is not to migrate the entire Rocq bot to OCaml 5.
Instead, the goal is to understand the new OCaml 5 concurrency model, compare it
with the current Lwt-based architecture, migrate one representative component as
a proof of concept, and propose a realistic migration plan for the rest of the
project.

The main deliverable is a concise and convincing explanation of how a transition
would be possible, informed by an experiment on a small part of the code, and a
plan that could be followed afterwards. Understanding and a clear plan matter
more than migrating many modules.

## Understand the current code
Limited number of representative modules. The goal is not to understand the
whole codebase, but to identify how asynchronous operations are currently
structured and where Lwt is used.

Tasks:
- the main entry point;
- locate `Lwt_main.run`;
- locate the incoming HTTP server;
- locate two outgoing HTTP requests;
- locate one use of `Lwt_process`;
- locate one use of `Lwt.async`;
- locate one use of `Lwt_list`;
- draw the current execution flow.

## OCaml 5 fundamentals
It is better to start from the problem than from the runtime details: why a
webhook bot needs asynchronous programming, how Lwt solves it today, and what
OCaml 5 / Eio change in practice.

Keep in mind three different layers:
- domains: parallelism on several CPU cores (useful to know, but secondary for this bot);
- effects and fibers: lightweight concurrency (suspend on I/O, then resume);
- Eio: the high-level library used to write concurrent I/O in direct style.

If a task is waiting on HTTP or process I/O, what matters is fibers / Eio, not
`Domain.spawn`.

Understand:
- the difference between concurrency and parallelism;
- why the bot mainly requires concurrency rather than parallelism;
- the role of domains in OCaml 5;
- the role of effect handlers;
- how fibers enable direct-style concurrency.

Domains are not the main subject of the bot project. The bot is mostly
I/O-bound, and creating domains is not required to replace most uses of Lwt.
Exercise: run two computations using `Domain.spawn`, then explain why domains
are not required for most webhook I/O.

It does not require becoming an expert in the low-level `Effect` module. It is
enough to understand the following model:

```text
Fiber starts -->
Perform an I/O operation -->
The operation cannot complete immediately -->
The fiber is suspended -->
The scheduler runs another ready fiber -->
The I/O operation completes -->
The suspended fiber resumes
```

Exercise: write or study one very small effect-handler example to understand the
mechanism, but do not attempt to implement a scheduler.

The project should use Eio as the high-level library rather than manipulating
low-level effects directly.

Source: The official OCaml manual section on parallel programming, especially domains.

## Understand Lwt's programming model
Since the current bot is implemented using Lwt, understanding its programming
model is essential before evaluating how it could be migrated to Eio.

It is sufficient to understand:
- why functions return `'a Lwt.t`;
- why asynchronous steps must be connected with `let*`;
- how errors propagate;
- how several Lwt operations run concurrently;
- what `Lwt.async` does;
- how the Lwt event loop schedules promises.

For the later comparison with Eio, it helps to keep a simple map in mind:
- `'a Lwt.t` / `let*` --> ordinary `'a` in direct style;
- `Lwt_main.run` --> `Eio_main.run`;
- `Lwt.async` / `Lwt.both` --> `Fiber.fork` / `Fiber.both`;
- `Lwt_process` --> `Eio.Process`;
- switches --> structured lifetimes (cancellation / cleanup).

## Understand Eio's programming model
Focus on a small subset of Eio. Eio is the recommended high-level concurrency
library for OCaml 5. It provides direct-style concurrent I/O programming built
on OCaml 5's effect system and will be the main library explored during this
project.

- `Eio_main.run`
- `Eio.Switch`
- `Eio.Fiber`
- `Eio.Time`
- `Eio.Path`
- `Eio.Process`
- `Eio.Stream`

Exercises:
- run two fibers concurrently;
- suspend one fiber with a timer;
- make one fiber fail;
- observe cancellation;
- create a bounded stream;
- implement one small producer-consumer example.

Source: Eio's official repository (README and examples).

## Incremental migration and `lwt_eio`

- why complete rewrites are risky;
- how Lwt and Eio can coexist;
- how to run old Lwt code under an Eio-owned event loop;
- what should remain only temporary bridge code.

Exercise: run a small Lwt function inside an Eio application.

Source: `lwt_eio` README.

## Prototype on the bot
Choose one representative but isolated component of the bot (for example Git
process execution, or one outgoing HTTP request, not both). The objective is to
evaluate how difficult the migration would be, rather than to migrate a large
portion of the application.

The prototype should remain small enough to be completed while being
representative of a real migration challenge.

Tasks:
- identify the current Lwt implementation;
- write characterization tests;
- implement the Eio version;
- preserve expected output and errors;
- compare both versions.

Timeouts and cancellation can be added if there is time left, but they are not
required for the prototype to be useful.

## Migration proposal
The final report should discuss:
- whether migration appears technically feasible;
- which parts of the bot should be migrated first;
- which dependencies and libraries would need to change;
- where `lwt_eio` can help as a temporary bridge;
- what benefits and drawbacks were observed;
- a proposed migration order for the complete project.

The report should be concise enough to explain the approach to someone who
already knows the bot and Lwt, but has not yet worked much with OCaml 5
concurrency.

## Summary
The learning path is:

```text
Understand the bot's use of Lwt -->
Learn concurrency versus parallelism -->
Understand effect handlers and fibers conceptually -->
Learn the essential Eio APIs -->
Experiment with lwt_eio -->
Migrate one isolated real operation -->
Use the experiment to produce a larger migration plan
```
