# Structural Visual Catalog (concept-teaching motion reference)

A worked catalog of "what concept → what structure to draw → what motion makes the rule visible". Pairs with the **structural-eval-tree** blueprint in [`../SKILL.md`](../SKILL.md) (the general skeleton: build-the-diagram in phases 1-3, animate-the-process in phases 4-5) and the **Structural visual** decision rules in `hyperframes-creative/SKILL.md`. Use this when the source concept has internal structure (data layout, call graph, state machine, execution order, type hierarchy) and a slide-deck paraphrase would lose the meaning.

For every entry: **source claim** (what the text says) → **structure** (what to actually draw) → **motion beats** (how the animation reveals the rule). Each is a worked example, not a generic recipe.

## 1. Programming-language evaluation

| Concept | Structure to draw | Motion beats |
|---|---|---|
| S-expression evaluation (`(+ 1 2)`) | SVG tree: root = function (circle, accent color), edges = children, leaves = literals (circles, value color) | (1) source code on the left; (2) root node spawns from source with `back.out(1.7)`; (3) edges draw via `stroke-dashoffset`, leaves fly in from source line; (4) root pulses, **particles ride edges** (set `attr: { cx, cy }` then tween) to leaves which turn green on arrival; (5) result pill appears bottom-left, tree breathes |
| Recursive function call | Stack frame ladder (each call = horizontal bar) with a "current frame" highlight | New frame slides in from top, locals pop into it, when it returns the bar collapses downward and the value returns to the caller's slot |
| Variable binding (`setq` vs `defvar`) | Two-column binding table: keys on left, values on right; a third "history" arrow showing overwrite events | `setq` writes a value, the cell flashes green; `defvar` on a populated key shows the cell briefly desaturating and a "skipped" badge |
| Lexical scope (closure) | Nested scope-chain ladder with arrows pointing from a lambda to each enclosing scope | Lambda cell appears in the deepest scope; arrows draw upward through the chain; a captured variable is highlighted in every scope frame it exists in |
| Type hierarchy (inheritance) | Tree: root = `object`, branches = classes, leaves = instances | An instance slides from the leaf up to the root, each branch it crosses highlights the type it conforms to |

## 2. Data structures and memory

| Concept | Structure to draw | Motion beats |
|---|---|---|
| Integers (atomic) | A single cell with `INT` type tag | The cell appears; a counter ticks `0 → 42` (counting-dynamic-scale) inside it, the number is the cell — the cell IS the data |
| Strings (char array) | A row of cells, one per character | Cells appear left-to-right with stagger; a highlight bar sweeps across (like a reading head) showing how `substring` slices |
| Cons cell / linked list `(1 2 3)` | A chain of two-cell pairs (head + tail-arrow) | Cells snap in one by one, each `tail` arrow draws toward the next cell; `car` highlights the head cell, `cdr` highlights the rest of the chain |
| Hash table (obarray) | A grid of buckets, with key→entry arrows | A key hashes (number→bucket pulses), entry cell grows, conflict resolution shows chaining |
| Stack vs heap | Two zones: a vertical stack with frames and a free-form heap cloud | Push: frame slides down onto stack; allocation: object grows in heap with an arrow from a stack variable pointing to it |
| Pointer chasing | A sequence of memory cells with arrow chains | Cursor moves from cell to cell, the cell it lands on lights up and reveals its content, the next pointer draws |

## 3. Algorithms and processes

| Concept | Structure to draw | Motion beats |
|---|---|---|
| BFS / DFS walk | A graph (nodes + edges) | Cursor visits nodes in order; visited nodes turn a "done" color, the frontier set pulses |
| Sorting (insertion / merge) | A row of cells, each a sortable element | Two-pointer cursors slide along the row, swap pulses fire on each comparison-swap |
| Recursion tree (Fibonacci, etc.) | The recursive call tree expanding | Calls spawn new branches until the leaf, then a "return" wave collapses each branch with a result value |
| Dynamic programming | A grid + an arrow path | The wavefront sweeps the grid; each cell flashes as it's filled; the answer path is highlighted at the end |
| Greedy / state machine | A state graph with a current-state highlight | States transition one by one, the active state pulses, the path trace is drawn as a polyline |

## 4. Networking and protocols

| Concept | Structure to draw | Motion beats |
|---|---|---|
| TCP three-way handshake | Two endpoints (client / server) + a horizontal timeline lane | SYN packet travels client→server, SYN-ACK travels back, ACK travels forward; each packet leaves a labeled ripple |
| HTTP request/response | Client node → server node, with a request body and a response body | Request body assembles on the left and travels right; server processes (a brief loading pulse); response body travels left, renders in the client |
| Packet routing | A network graph (routers + edges with weights) | A packet hops router-to-router, each hop labels the routing table consulted, the chosen path lights up |

## 5. Systems and OS

| Concept | Structure to draw | Motion beats |
|---|---|---|
| Process state machine | States laid out in a circle (new / ready / running / waiting / terminated) | A token moves state-to-state with arrows drawn as it transitions, the reason for each transition is captioned on the arrow |
| Memory page table | A virtual-address column mapping to physical frames | Lookup arrow goes from virtual address to a frame, the frame cell pulses with the page's content |
| File descriptor table | A small table where each row = FD number, value = pointer to inode | Open: row populates and the inode card grows; close: row empties |
| Producer-consumer | Two boxes with arrows + a bounded buffer between | Producer places items (cells) into the buffer, consumer removes them; buffer fill state visibly changes |

## 6. Biology and science (uses the same skeleton, different content)

| Concept | Structure to draw | Motion beats |
|---|---|---|
| Mitosis (4 phases) | A single cell that visibly splits across scenes | Each scene = one phase: DNA condenses, nuclear envelope breaks, chromosomes line up, sister chromatids separate, two cells emerge |
| Krebs cycle | A circular diagram of intermediates with arrows | Each intermediate pulses as it's reached; the cycle rotation makes the loop self-evident |
| DNA replication | Two strands separating with a replication fork | Helicase wedge moves along the strands, two new strands synthesize behind it in complementary colors |
| Action potential | A voltage-time curve with threshold bands | A sweep cursor moves along the curve, the voltage line draws in real-time, threshold crossings fire a "spike" particle |

## 7. Math and logic

| Concept | Structure to draw | Motion beats |
|---|---|---|
| Derivative (as slope) | A function curve + a tangent line at a moving point | A dot slides along the curve, the tangent line rotates and rescales to match, slope value updates in a HUD |
| Set union / intersection | Two Venn circles | Each set's members appear inside its circle; the overlap region highlights when the relevant operation is named |
| Logic gate (AND / OR) | Two input wires + one gate symbol + one output wire | Input values pulse true/false; gate's symbol briefly highlights on each combination; output wire shows result |
| Proof tree | A bottom-up tree where leaves = axioms and root = theorem | Each rule application is a "parent" node that consumes its children's proofs; the root is the proven theorem |

## Cross-cutting motion patterns

These four motion patterns recur across most entries — they're the building blocks of "animate the process":

1. **Build-the-structure first, animate-the-process second.** Phases 1-3 (appearance, edges, leaves) take ~30% of the scene's duration; phases 4-5 (process, result) take the remaining 70%. If the structure isn't fully visible before the process starts, the viewer can't follow what's happening.
2. **The cursor / particle is the explainer.** A moving marker — a colored dot, a cursor, a packet — is the strongest single visual signal. It traces the path the rule describes, so the rule is *the path*, not a caption.
3. **State change is a color or scale pulse, not a tween.** A cell going from "unprocessed" to "processed" should pulse (1.0 → 1.2 → 1.0) and shift color once. Don't tween the color over 0.5s — it looks like the cell is unsure. A 0.25s pulse + instant color shift is decisive.
4. **The result is the last beat and it gets room.** The final value (a number, a path, a yes/no) should land with a `back.out(1.4)` and a breathing box-shadow for 0.5-1s. Rushing it makes the rule feel like a process that doesn't conclude.

## How to use this catalog

- Pick the row that matches the concept being explained.
- Copy the **structure** as the SVG/DOM layout (no copying the motion — generate that fresh).
- Match the **motion beats** to your 5-phase blueprint (build / edges / leaves / process / result); durations in the structural-eval-tree blueprint are the baseline, ±20% per scene.
- If the concept is **not** in the catalog, ask: *what's the topology of the data/process?* and pick the closest row's structure as a starting point. Linear pipeline ↔ row of cells, branching ↔ tree, two-party exchange ↔ endpoint + timeline lane, internal-state ↔ state machine circle.
