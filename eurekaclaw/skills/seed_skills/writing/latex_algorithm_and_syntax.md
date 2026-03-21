---
agent_roles:
- writer
created_at: '2026-03-20T06:30:46.018152'
description: When writing LaTeX papers, place algorithms in proper LaTeX algorithm
  environments and perform a syntax sanity check before finalizing the output.
name: latex_algorithm_and_syntax
pipeline_stages:
- writing
source: seed
success_rate: 1.0
tags:
- writing
- latex
- algorithm
- pseudocode
- syntax
- compilation
- paper
usage_count: 0
version: '1.0'
---

# LaTeX Algorithms and Syntax Sanity

## When to apply

Use when:
- the Writer Agent is generating a LaTeX paper
- the paper contains an algorithm, pseudocode block, or procedural method
- the draft includes custom environments, many equations, or fragile LaTeX structure

This skill is only for **LaTeX output**. Do not apply it to Markdown output.

## Main rules

### 1. Algorithms must use LaTeX algorithm environments

If the paper includes any algorithmic procedure, present it in a LaTeX algorithm environment rather than plain prose or ad hoc bullet points.

Preferred pattern:

```latex
\begin{algorithm}[t]
\caption{Algorithm Name}
\label{alg:name}
\begin{algorithmic}[1]
\STATE ...
\FOR{...}
\STATE ...
\ENDFOR
\RETURN ...
\end{algorithmic}
\end{algorithm}
```

Use:
- `algorithm` for the floating environment
- `algorithmic` or `algpseudocode`-style commands for the pseudocode body

If the paper contains multiple procedures, give each one:
- a caption
- a label
- meaningful step names

Do not render algorithms as:
- raw itemized lists
- plain paragraphs beginning with “Algorithm:”
- verbatim-style code blocks pretending to be pseudocode

### 2. Algorithm prose should match theorem style

Before or after the algorithm environment, briefly explain:
- what the algorithm takes as input
- what it outputs
- what the key update rule or decision rule is
- where the guarantee is proved

The algorithm block should be readable on its own, but the surrounding prose should connect it to the theorem statements and proof.

### 3. Perform a LaTeX syntax sanity check before finalizing

Before finalizing the LaTeX output, do a manual syntax pass and verify:
- every `\begin{...}` has a matching `\end{...}`
- braces `{...}` are balanced
- every displayed equation is properly closed
- every theorem/proof/algorithm environment is properly nested
- every `\cite{...}` key is syntactically valid
- labels and refs are not obviously malformed
- no Markdown syntax has leaked into the LaTeX output
- every custom command used in the body is either a standard LaTeX command or explicitly defined in the file preamble

If the paper uses algorithm environments, also verify:
- the required packages are present in the preamble or assumed by the template
- the algorithm environment is not nested illegally inside theorem/proof environments in a broken way
- the caption and label are inside the algorithm float, not floating as plain text

### 4. Detect and add required packages in the file

If the LaTeX output uses an environment or command that requires a package, explicitly ensure the package is included in the file preamble.

At minimum, check for:
- `algorithm` / `algorithmic` environments
- `algpseudocode` commands such as `\State`, `\For`, `\While`
- theorem environments
- color commands such as `\textcolor`
- hyperlinks and citations

If an algorithm environment appears, the file should include a compatible package setup such as:

```latex
\usepackage{algorithm}
\usepackage{algorithmic}
```

or

```latex
\usepackage{algorithm}
\usepackage{algpseudocode}
```

Do not assume the template already loads these packages unless the file itself clearly shows that it does.
If the needed package is missing, add it to the preamble in the generated file.

### 5. Detect undefined custom macros and define them in the file

If the paper uses a nonstandard macro such as:
- `\KL`
- `\TV`
- `\Reg`
- `\argmax`
- `\E`, `\P`, `\Var`
- domain-specific shorthand such as `\poly`, `\bellman`, or `\cF`

then do one of the following:
- define the macro explicitly in the preamble with `\newcommand` or `\DeclareMathOperator`
- or replace it by standard LaTeX if the shorthand is unnecessary

Do not leave a command in the paper unless one of these is true:
- it is a standard LaTeX command
- it is provided by a package already included in the preamble
- it is explicitly defined in the file

Examples:

```latex
\newcommand{\KL}{\mathrm{KL}}
\newcommand{\TV}{\mathrm{TV}}
\newcommand{\E}{\mathbb{E}}
\newcommand{\P}{\mathbb{P}}
\DeclareMathOperator*{\argmax}{arg\,max}
\DeclareMathOperator*{\argmin}{arg\,min}
```

If the generated paper uses shorthand notation, check the preamble and add the missing macro definitions there.
Do not assume a conference template defines these commands for you.

## Default package expectations

When writing LaTeX with algorithms, assume the paper should support packages such as:

```latex
\usepackage{algorithm}
\usepackage{algorithmic}
```

or an equivalent setup such as:

```latex
\usepackage{algorithm}
\usepackage{algpseudocode}
```

Prefer one consistent pseudocode style throughout the paper.
Do not mix multiple incompatible algorithm packages unless the template clearly requires it.

Also check the rest of the file for package needs. Typical examples:

```latex
\usepackage{amsmath, amssymb, amsthm}
\usepackage{xcolor}
\usepackage{hyperref}
\usepackage{natbib}
```

Before finalizing, scan the actual commands used in the paper and confirm the corresponding packages appear in the preamble.

Likewise, scan the actual macros used in the paper and confirm that every nonstandard macro is defined in the preamble.

## Proof-writing interaction

When an algorithm is central to a theorem:
- state the algorithm first in an algorithm environment
- then state the guarantee as a theorem, proposition, or lemma
- in the proof, refer back to the algorithm by label, e.g. `Algorithm~\ref{alg:name}`

Do not bury the actual procedure inside a proof if the algorithm is a first-class contribution.

## Common mistakes to avoid

- **Algorithm as prose only**: if it is really an algorithm, typeset it as one.
- **Broken environment nesting**: opening `proof`, `theorem`, `algorithm`, and display math environments in the wrong order.
- **Unbalanced math delimiters**: especially `\[`, `\]`, `$$`, and `\left ... \right`.
- **Package mismatch**: using `\STATE` / `\FOR` syntax without an algorithmic package.
- **Label without caption**: algorithm labels should normally accompany a visible caption.
- **Markdown leakage**: headings like `##`, bold markers like `**...**`, or fenced code blocks should not appear in LaTeX output.

## Response template

When generating a LaTeX paper with algorithms:

1. Write the relevant procedure in an `algorithm` environment.
2. Give it a caption and label.
3. Reference it from the surrounding theorem/proof text.
4. Detect which LaTeX packages are required by the commands and environments you used.
5. Ensure those packages are explicitly included in the preamble of the file.
6. Detect any custom macros you introduced and define them explicitly in the preamble.
7. Perform a syntax sanity pass before returning the final LaTeX.
8. If uncertain about a fragile block, simplify the LaTeX rather than risking malformed output.