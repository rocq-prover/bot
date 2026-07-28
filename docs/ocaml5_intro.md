# OCaml 5

OCaml 5 was released on December 16, 2022. The latest stable release is OCaml
5.5.0, released on June 19, 2026.

OCaml 5 keeps the functional, imperative, object-oriented, and module-system
features of OCaml 4, but replaces the runtime with one designed for:
- true shared-memory parallelism;
- lightweight concurrency based on effect handlers;
- multiple CPU cores;
- a parallel-aware garbage collector;
- multicore synchronization primitives such as atomics;
- modern language and standard-library evolution.

This document has two parts:
1. what to know about OCaml 5 in general;
2. how that knowledge applies to migrating the Rocq bot.

---

# Part I - Knowing OCaml 5

## 1. Concurrency and parallelism

These are different needs, and OCaml 5 provides different tools for them.

### Concurrency

Concurrency means that several tasks are logically in progress. They may
alternate:

```text
Task A runs
Task A waits
Task B runs
Task B waits
Task A continues
```

This is especially useful for:
- network servers;
- file I/O;
- database calls;
- HTTP requests;
- timers;
- event-driven applications.

The tasks do not necessarily run simultaneously.

### Parallelism

Parallelism means several computations are actually running at the same time on
different CPU cores:

```text
Core 1: Task A
Core 2: Task B
Core 3: Task C
```

This is useful for CPU-intensive work such as:
- model checking;
- cryptographic computation;
- image processing;
- simulations;
- search algorithms;
- numerical computation;
- compiling independent modules;
- processing large arrays.

OCaml 5 deliberately separates the two: domains for parallelism, and effects
(or threads) for concurrency.

## 2. What changed from OCaml 4 to OCaml 5?

The main change is the runtime architecture.

In OCaml 4:
- only one OCaml thread can execute OCaml code at a time;
- system threads could still perform concurrent I/O;
- CPU-bound OCaml threads could not run simultaneously;
- parallel computation generally required multiple processes.

In OCaml 5:
- multiple OCaml computations can run at the same time on different CPU cores;
- shared OCaml values can be accessed by multiple domains;
- the runtime and garbage collector understand parallel execution;
- effect handlers make it possible to implement lightweight fibers, schedulers,
  asynchronous I/O, generators, and structured concurrency.

The central model is:

```text
OCaml 5
|---- Domains --> parallelism across CPU cores
|---- Threads --> operating-system threads (also used under domains)
|---- Effects/fibers --> lightweight concurrency
|---- Atomics/mutexes --> shared-memory synchronization
|---- Multicore GC --> memory management for all domains
```

## 3. Parallelism with domains

A domain is OCaml 5's unit of parallel execution.

Each domain:
- maps approximately one-to-one to an operating-system thread;
- has its own runtime state;
- has its own minor-heap allocation area;
- may execute OCaml code simultaneously with other domains;
- can share values with other domains.

The basic interface is the `Domain` module.

Example:

```ocaml
let () =
  let domain =
    Domain.spawn (fun () ->
      print_endline "Running in another domain";
      42)
  in
  print_endline "Running in the main domain";
  let result = Domain.join domain in
  Printf.printf "Result = %d\n" result
```

Conceptually:

```text
Main domain                New domain
----------                 ----------
Domain.spawn   ---->       compute 42
continue working           finish
Domain.join    <----       return 42
```

`Domain.spawn` starts the computation. `Domain.join` waits for it and obtains
its result.

Domains are heavyweight. They are not meant to be created for every tiny
operation, because each domain has its own runtime structures and
operating-system thread.

The official manual recommends avoiding more active domains than available CPU
cores. The runtime also limits how many domains can be active at once.

This is usually a poor design:

```ocaml
let rec parallel_fib n =
  if n < 2 then n
  else
    let d1 = Domain.spawn (fun () -> parallel_fib (n - 1)) in
    let d2 = Domain.spawn (fun () -> parallel_fib (n - 2)) in
    Domain.join d1 + Domain.join d2
```

It recursively creates an enormous number of domains. Instead, create a fixed
pool of domains and submit smaller tasks to it.

## 4. Domainslib and parallel workloads

For most data-parallel or divide-and-conquer programs, the standard
recommendation is to use a higher-level library such as `domainslib`, rather
than creating domains by hand.

Example of parallel array processing:

```ocaml
open Domainslib

let () =
  let workers = max 1 (Domain.recommended_domain_count () - 1) in
  let pool = Task.setup_pool ~num_domains:workers () in
  let values = Array.init 1_000_000 Fun.id in
  Task.run pool (fun () ->
    Task.parallel_for pool
      ~start:0
      ~finish:(Array.length values - 1)
      ~body:(fun i ->
        values.(i) <- values.(i) * values.(i)));
  Task.teardown_pool pool
```

The important design is:

```text
Create worker pool once
        |
Submit many small tasks
        |
Workers reuse existing domains
        |
Destroy pool at shutdown
```

Parallel reduction, conceptually:

```text
[section 1] -> worker 1 -> partial sum
[section 2] -> worker 2 -> partial sum
[section 3] -> worker 3 -> partial sum
                |
            combine results
```

Parallelization is useful only when each task contains enough work to
compensate for:
- task scheduling;
- communication;
- synchronization;
- cache effects;
- garbage collection;
- combining results.

A small array may be slower in parallel than sequentially.

## 5. Sharing values and data races

Immutable OCaml values can generally be shared freely between domains:

```ocaml
let configuration =
  [
    ("host", "localhost");
    ("port", "8080");
  ]
```

Since no domain can modify the list or its strings through normal OCaml
operations, concurrent reads do not create a data race. This is one of the
major advantages of functional programming in a multicore setting.

A good parallel architecture often follows this pattern:

```text
Immutable input
     |
Independent parallel calculations
     |
Immutable partial results
     |
Combine results
```

The less shared mutation you have, the easier the program is to reason about.

Sometimes every domain needs its own independent value, for example:
- a random-number generator;
- a reusable buffer;
- statistics;
- a parser state;
- a connection cache;
- logging context.

OCaml provides domain-local storage through `Domain.DLS`.

When domains must share mutable state, synchronize explicitly (for example with
`Atomic`, `Mutex`, or message passing). OCaml's type system does not
automatically prevent data races. The official migration documentation warns
that parallel domains performing unsynchronized shared mutation can race.

## 6. Concurrency with effect handlers

Effect handlers are the second foundational feature of OCaml 5. They generalize
exceptions and are the basis for lightweight concurrency (fibers, schedulers,
direct-style async I/O).

With an exception:

```text
computation raises
     |
control transfers to handler
     |
original computation is abandoned
```

With an effect:

```text
computation performs effect
           |
control transfers to handler
           |
handler receives suspended continuation
           |
handler may resume the computation
```

Effect handlers support abstractions such as:
- fibers;
- async/await-style libraries;
- generators;
- coroutines;
- cooperative schedulers;
- resumable operations;
- parser control;
- simulation;
- dependency injection;
- tracing;
- custom interpreters.

OCaml 5.0 introduced effect handlers, and OCaml 5.3 added dedicated syntax for
deep effect handlers.

An effect is declared by extending `Effect.t`:

```ocaml
open Effect
open Effect.Deep

type _ Effect.t += Ask : string Effect.t
```

This says that `Ask` is an operation that returns a string.

A computation may perform it:

```ocaml
let greet () =
  let name = perform Ask in
  "Hello, " ^ name
```

A handler defines its meaning:

```ocaml
let result =
  try greet () with
  | effect Ask, continuation -> continue continuation "World"
```

The result is `Hello, World`.

The central object is the continuation. It represents the suspended
computation:

```ocaml
let name = [waiting here] in
  "Hello, " ^ name
```

When the handler executes `continue continuation "World"`, the suspended
computation resumes as though `perform Ask` had returned `"World"`.

## 7. Effects versus exceptions

Exception:

```ocaml
raise Not_found
```

Handler:

```ocaml
try computation () with
| Not_found -> fallback
```

The abandoned computation does not normally resume.

Effect:

```ocaml
perform Ask
```

Handler:

```ocaml
try computation () with
| effect Ask, k -> continue k "answer"
```

The computation resumes.

A useful mental model is:

```text
Exception = escape
Effect    = request an operation from an enclosing handler
```

OCaml continuations are linear, or one-shot. After capturing a continuation, it
may be resumed only once with `continue k value`, or terminated once with
`discontinue k exception_value`. Trying to resume the same continuation again
raises `Effect.Continuation_already_resumed`.

One-shot continuations are cheaper than general multi-shot continuations, and
they fit the goal of implementing efficient concurrency. However, OCaml does
not statically verify that every continuation is eventually resumed or
discontinued, so careless handlers can retain memory or resources.

## 8. Deep and shallow handlers

OCaml provides two broad forms of effect handler.

### Deep handlers

A deep handler remains installed when the continuation resumes:

```text
perform effect
     |
handler handles it
     |
continuation resumes under same handler
     |
later effects are also handled
```

Deep handlers are usually easier for schedulers and repeated operations.
OCaml 5.3's `effect` syntax installs deep handlers.

### Shallow handlers

A shallow handler handles one suspension step. When the continuation is
resumed, the handler must be reinstalled explicitly if further effects should
be processed.

Shallow handlers give finer control, but they are more complex. There is no
dedicated surface syntax for them; they are used through `Effect.Shallow`.

## 9. Effects are not statically tracked

OCaml 5 does not have a static effect system.

Given:

```ocaml
val f : int -> string
```

the type does not tell whether `f` may:
- perform an effect;
- read a file;
- yield to a scheduler;
- raise an exception;
- log;
- access mutable state.

If an effect reaches the top of the program without a matching handler, OCaml
raises `Effect.Unhandled`.

## 10. Eio: high-level concurrent I/O

For new effect-based concurrent OCaml applications, Eio is an important
ecosystem library. Fibers and structured concurrency are usually consumed
through Eio (or a similar library), not by writing custom effect handlers for
everyday I/O.

Eio provides abstractions for:
- fibers;
- networking;
- files;
- clocks;
- processes;
- cancellation;
- structured concurrency;
- switches;
- synchronization;
- environment capabilities.

A typical Eio program looks conceptually like:

```ocaml
open Eio.Std

let main env =
  let clock = Eio.Stdenv.clock env in
  Eio.Time.sleep clock 1.0;
  traceln "Finished"

let () = Eio_main.run main
```

(`traceln` comes from `Eio.Std`.)

The distinction is:

```text
Effect handlers
    low-level language/runtime mechanism

Eio
    high-level concurrency and I/O library
```

## 11. Lwt versus Eio

Lwt and Eio solve overlapping but not identical problems.

### Lwt

Lwt uses explicit promises:

```ocaml
operation () >>= fun result -> next_operation result
```

or binding syntax:

```ocaml
let%lwt result = operation () in
next_operation result
```

(Many codebases also use `Lwt.Syntax` with `let*`.)

Strengths include:
- mature ecosystem;
- long-established libraries;
- broad package compatibility;
- portability;
- large existing codebases;
- support for older OCaml versions.

### Eio

Eio uses effects and fibers, which allows direct-style code:

```ocaml
let result = operation () in
next_operation result
```

Strengths include:
- structured concurrency;
- explicit cancellation scopes;
- direct-style APIs;
- capability-based environment;
- design centered on OCaml 5.

### Two separate decisions

Moving a project to OCaml 5 does not automatically require rewriting Lwt code
in Eio.

```text
Decision 1: compile and run on OCaml 5
Decision 2: redesign concurrency around Eio
```

Decision 1 is often much smaller. Some projects are already on Decision 1 and
only need to evaluate Decision 2.

A common incremental strategy is:
1. make the project compile under OCaml 5 (if it does not already);
2. update incompatible dependencies and C stubs;
3. test existing Lwt behavior on the new runtime;
4. identify whether there are real CPU-bound workloads for domains;
5. evaluate Eio separately for I/O concurrency;
6. migrate subsystems only when the benefits justify it;
7. use bridges such as `lwt_eio` during the transition.

## 12. What OCaml 5 does not provide automatically

OCaml 5 does not automatically give:
- automatic parallelization of ordinary functions;
- static prevention of data races;
- static effect tracking;
- automatic cancellation of domains;
- guaranteed speedup;
- automatic conversion of Lwt programs into Eio;
- safe lock-free data structures by default;
- isolation between domains;
- distributed computing across machines.

Parallel execution and concurrency redesign still have to be designed
explicitly.

## 13. Language evolution after OCaml 5.0

OCaml 5 is not only multicore. Releases 5.1 through 5.5 have continued adding
language, compiler, runtime, and standard-library improvements.

Highlights of OCaml 5.5 include:
- module-dependent functions;
- polymorphic functions as function arguments;
- relocatable compiler support;
- extended local definitions;
- substring search and replacement functions;
- external types;
- garbage-collector improvements;
- approximately 60 new standard-library functions;
- Windows runtime improvements;
- numerous compiler and bug fixes.

These matters for day-to-day OCaml 5 development, but they are separate from
the concurrency and parallelism model.

## 14. Recommended mental model

Use three levels.

### Level 1: sequential functions

Write most logic as ordinary pure or mostly pure functions:

```ocaml
val analyse_state : model -> state -> result
```

### Level 2: fibers for waiting

Use fibers (typically via Eio) for operations that wait:

```text
HTTP
files
sockets
timers
databases
subprocesses
```

### Level 3: domains for CPU work

Use a bounded domain pool for expensive independent computation:

```text
parsing
hashing
search
analysis
simulation
proof computation
```

This gives:

```text
Pure functional core
      +
Fiber-based I/O shell
      +
Bounded parallel worker pool
```

That is a strong general architecture for OCaml 5 applications. Not every
program needs Level 3. Many I/O services mainly need Levels 1 and 2.

## 15. What needs to be relearned

If you write only sequential programs, very little changes.

You can continue using:
- ADTs;
- pattern matching;
- recursion;
- lists and arrays;
- modules and functors;
- objects;
- GADTs;
- polymorphic variants;
- `dune`, `opam`.

The new concepts become important when you use:
- multiple domains;
- shared mutable state;
- effect-based libraries;
- concurrency;
- C bindings;
- performance-sensitive allocation;
- runtime monitoring.

The key new vocabulary is:
- Domain
- Fiber
- Effect
- Handler
- Continuation
- Atomic
- Data race
- Memory ordering
- Structured concurrency
- Parallel GC
- Safepoint

## 16. What to learn first

A complete OCaml 5 map covers both parallelism and concurrency. Projects differ
in which side they need first.

### Stage 1: core concepts

```text
concurrency vs parallelism
domain vs thread vs fiber
immutable sharing vs mutable sharing
data race
structured concurrency
```

### Stage 2: parallelism with domains

Practice:
- `Domain.spawn`;
- `Domain.join`;
- exception propagation;
- domain-local storage;
- bounded worker pools.

### Stage 3: synchronization for shared mutable state

Practice:
- `Atomic`;
- `Mutex`;
- condition variables;
- semaphores;
- message passing;
- ownership-based state.

### Stage 4: domainslib

Implement:
- parallel array map;
- parallel reduction;
- divide-and-conquer;
- parallel tree traversal;
- work granularity thresholds.

### Stage 5: effects

Understand:
- `perform`;
- effect declarations;
- handlers;
- continuations;
- `continue`;
- `discontinue`;
- deep versus shallow handlers;
- one-shot continuation rules.

### Stage 6: Eio and direct-style concurrency

Build:
- concurrent timers;
- a TCP server;
- an HTTP client/server;
- concurrent request processing;
- cancellation scopes;
- resource-safe services.

### Stage 7: migration engineering

Study:
- dependency compatibility;
- C bindings;
- global state;
- bridges such as `lwt_eio`;
- race testing;
- TSan;
- runtime events;
- performance benchmarking.

For an I/O-heavy Lwt service, Stages 1, 5, 6, and 7 are usually the critical
path; Stages 2 to 4 remain part of knowing OCaml 5, but may stay secondary
until a measured CPU bottleneck appears.

---

# Part II - Migrating the Rocq bot

The bot already compiles and deploys on OCaml 5.2 (`release.Dockerfile`). The
remaining work is not a classical OCaml 4 to OCaml 5 port. It is to strengthen
the baseline, understand what a move from Lwt toward Eio would mean for this
codebase, and validate any experiment carefully.

## Migration status (this branch)

Completed for the compiler / local-setup track:

| Phase | Status | Notes |
| --- | --- | --- |
| Phase 1: baseline | Done | Local `dune build` / `dune runtest` work; `tests/` alcotest suite plus expect tests; CI runs `@tests/runtest`. |
| Phase 2: local env aligned with deploy | Done | Local opam switch on OCaml 5.2; `dune-project` pins `(ocaml (and (>= 5.2.0) (< 5.3.0)))` for both packages. |
| Phase 3: dependency surface | Done | Dependencies resolve on 5.2; RNG uses `mirage-crypto-rng.unix` / `Mirage_crypto_rng_unix.use_default`; GraphQL schemas refresh only via `@update-schemas`. |
| Phase 4: keep Lwt architecture | Done | Confirmed: still Lwt + Cohttp Lwt on OCaml 5.2; no Domains / Eio introduced. |
| Phase 5: document shared mutable state | Not started | Needed before any multicore / multi-domain experiment. |
| Phase 6: prototype one Eio component | Not started | Optional next experiment; not required for the OCaml 5 compile track. |
| Phase 7: validate against real bot path | Partial | Local build/tests pass; full smoke / deploy validation of an Eio prototype still open. |

What this means in practice: the OCaml 5.2 compile path is in place locally and in
metadata. The open work is documentation of shared state and any later Lwt-to-Eio
experiment, not getting the bot onto the OCaml 5 compiler.

Several large OCaml projects have already moved to OCaml 5, or from Lwt toward
Eio. Their approaches are useful to study before planning the next steps for
the bot.

## Examples from other projects

### Octez (Tezos)

Octez is a large Lwt-based system. Its migration to OCaml 5 was deliberate and
incremental.

Method, in summary:
- first compile and run on OCaml 5 while keeping Lwt;
- update the dependency set and fix runtime assumptions (C stubs, Random,
  flaky tests, package pins);
- compare performance and memory against OCaml 4 before changing concurrency;
- only later introduce Eio selectively (for example worker pools in `lib_bees`
  and an Eio-owned event loop);
- use `Lwt_eio` so existing Lwt code can still run under the new loop.

Lesson: moving to OCaml 5 and redesigning concurrency are two different
decisions. Octez did the compiler migration first, then evolved concurrency
piece by piece. The bot is in a similar situation: the compiler step is
already done.

Useful references:
- Octez OCaml 5 migration MR: https://gitlab.com/tezos/tezos/-/merge_requests/15404
- Octez release notes around v22 (OCaml 5 compiler)

### Irmin

Irmin went further on the concurrency side: the core library was converted from
Lwt monadic style to Eio direct style (Irmin 4).

Method, in summary:
- develop the Eio conversion on a long-lived branch;
- rewrite the store API so effectful operations return ordinary values instead
  of `'a Lwt.t`;
- keep `lwt_eio` where some packages still need to talk to Lwt code;
- for downstream users, provide a compatibility layer (`irmin-lwt`) that wraps
  the Eio API behind `Lwt.t` types.

The intended path for consumers is:
1. switch from Irmin 3 to `irmin-lwt` (same monadic style, Eio underneath);
2. later drop the shim and use Irmin 4 direct style, module by module.

Lesson: when changing concurrency, migrate one clear surface first, then keep
a temporary bridge. For the bot, that means one isolated component rather than
a full rewrite.

Useful references:
- Irmin Eio risk / promotion discussion: https://github.com/mirage/irmin/issues/2401
- Irmin Lwt shim PR: https://github.com/mirage/irmin/pull/2406

### Ecosystem libraries: Cohttp, ocaml-tls, and similar

Several libraries did not force every user to migrate at once. Instead they
added parallel backends:
- `cohttp-lwt` / `cohttp-eio`;
- `tls-lwt` / `tls-eio`;
- and similar dual packages in the Mirage / Tarides ecosystem.

Method, in summary:
- keep the protocol/core logic scheduler-agnostic when possible;
- provide a dedicated Eio backend next to the Lwt one;
- port backends line by line, testing along the way (this is how `tls-eio` was
  derived from `tls-lwt` in practice);
- let applications choose the backend, or migrate one dependency at a time
  through `lwt_eio`.

Lesson: the bot depends on Cohttp Lwt today. Any HTTP migration would likely
go through `cohttp-eio` (or another Eio HTTP stack) one call site at a time,
not by rewriting the whole server in one step.

### Ocsigen

Ocsigen (the original home of Lwt) has started moving toward Eio as well.

Method, in summary:
- rewrite interfaces toward direct style;
- keep bridge libraries so existing Lwt applications can continue;
- develop tooling to automate mechanical rewrites (`let*` / binds flattening,
  and similar), while accepting that full automation is hard because Lwt
  concurrency is often implicit.

Lesson: bridges and partial automation help, but webhook handlers with
`Lwt.async`, cancellation, and process I/O still need human review.

### Common pattern for the bot

Given the examples above, the useful shape for this repository is:

```text
Strengthen baseline and local OCaml 5.x setup
        |
Keep the current Lwt architecture
        |
Prototype one isolated Eio component (with lwt_eio if needed)
        |
Compare behavior and document a migration order
        |
Only later migrate more subsystems and remove bridges
```

## Phase 1: establish a baseline for the bot

Status: done for the current tree.

The goal is a reproducible picture of the current bot before any concurrency
experiment.

Done:
- local opam switch on OCaml 5.2;
- `dune build` and `dune runtest` pass locally;
- `release.Dockerfile` remains on OCaml 5.2;
- expect tests for `String_utils` / `Git_utils`, plus the `tests/` alcotest
  suite;
- CI runs `dune build @tests/runtest --ignore-promoted-rules`.

Notes:
- prefer `dune build @tests/runtest` when you only want the `tests/` suite (same
  as CI);
- full `dune runtest` also runs bot-components inline expect tests.

## Phase 2: align the local environment with deploy

Status: done.

Production already uses OCaml 5.2:

```dockerfile
FROM ocaml/opam:alpine-3.20-ocaml-5.2 AS builder
```

Locally:

```bash
opam switch create . ocaml-base-compiler.5.2.0
# or another 5.x close to deploy, then:
eval $(opam env)
opam install . --deps-only --with-test --working-dir
```

`dune-project` now pins the compiler line for both `coq-bot` and
`bot-components`:

```lisp
(ocaml (and (>= 5.2.0) (< 5.3.0)))
```

That pin is the source of truth: with `(generate_opam_files true)`, dune writes
it into the generated `.opam` files. Do not hand-edit only the `.opam` files.

## Phase 3: check the bot's dependency surface

Status: done for the current dependency set.

The Docker path already installs dependencies on OCaml 5.2, so resolution is
mostly settled. Packages the bot actually uses:
- `lwt`, `cohttp-lwt`, `cohttp-lwt-unix`, `lwt_ssl` / `ssl`;
- `mirage-crypto` and `mirage-crypto-rng` (Unix backend:
  `mirage-crypto-rng.unix`, initialized with
  `Mirage_crypto_rng_unix.use_default` in `src/bot.ml`);
- `graphql_ppx` and checked-in GraphQL schemas under
  `bot-components/github/` and `bot-components/gitlab/`;
- Jane Street `base` / `ppx_expect`;
- `camlzip`, `yojson`, `toml`.

Schema regeneration is explicit only:

```bash
dune build @update-schemas
```

Normal `dune build` / `dune runtest` must not rewrite the schema JSON files.

There are no project-owned C stubs or ctypes bindings in `src` or
`bot-components`. Native code enters only through dependencies (for example
`ssl`, `camlzip`).

## Phase 4: keep the current Lwt architecture

Status: done (confirmed, not rewritten).

The bot already runs its Lwt design on OCaml 5:
- `Lwt_main.run` in `src/bot.ml`;
- `Cohttp_lwt_unix.Server` for incoming webhooks;
- many `Lwt.async` handlers so HTTP can answer quickly;
- `Lwt_process` / `Lwt_unix` in git helpers for git and shell commands;
- `Lwt_list` and related helpers in the actions code.

Do not introduce Domains or rewrite to Eio in this phase. The existing Lwt bot
builds and tests on the local 5.2 switch.

## Phase 5: document shared mutable state before any multicore step

Status: not started.

While the bot stays on single-domain Lwt, the current shared state is normal.
Before any Domain or multi-domain Eio experiment, record and treat carefully:
- installation token caches in the GitHub installations code;
- github / gitlab mapping hashtables filled from config and updated in git
  helpers;
- `Lwt_preemptive.detach` around camlzip in `bot-components/utils/HTTP_utils.ml`.

The app code has little use of `ref`, `Lazy`, or custom finalizers. Do not
share those hashtables across Domains without a redesign.

## Phase 6: prototype one Eio component, not Domain parallelism

Status: not started.

The bot is mostly I/O-bound: webhooks, Cohttp client calls, git and shell
processes. Heavy Coq minimization runs outside the OCaml process. Domain
parallelism is not the main lever here.

Instead:
- pick one isolated surface, for example a git command helper or one
  outgoing HTTP request;
- write characterization tests for the current Lwt behavior;
- implement an Eio version, using `lwt_eio` if the rest of the bot still runs
  under Lwt;
- compare outputs and errors;
- leave timeouts / cancellation as optional extras.

Do not Domain-parallelize webhook handlers that share the hashtables from
Phase 5.

## Phase 7: validate the experiment against the real bot path

Status: partial for the OCaml 5.2 baseline; open for any Eio prototype.

Validation should follow the bot's actual delivery path, not a generic
multicore checklist.

Already in place for the baseline:
- `dune build` / `dune runtest` locally on OCaml 5.2;
- CI alias `@tests/runtest` with `--ignore-promoted-rules`;
- Docker image on the same OCaml 5.2 line as deploy.

Still needed when an Eio experiment lands:
- characterization tests for the chosen component;
- a smoke test of the running bot (local or Heroku-like) before and after the
  prototype lands on a branch.

If the experiment stays single-domain with `lwt_eio`, that is enough for a
first report. TSan, runtime events, and stress tools become relevant mainly if
a later step introduces Domains or multi-domain Eio.
