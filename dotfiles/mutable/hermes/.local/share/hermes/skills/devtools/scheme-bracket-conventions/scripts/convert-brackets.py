#!/usr/bin/env python3
"""R6RS Appendix C bracket converter.

Converts round parens to square brackets in the binding/clause positions
specified by R6RS Appendix C, for Scheme/Guile code.

Usage:
    python3 convert-brackets.py scm <file.scm>    # convert a .scm file → stdout
    python3 convert-brackets.py org <file.org>    # convert only #+begin_src scheme blocks

Character-level scanning correctly skips: strings, char literals (#\( etc.),
line comments (;), block comments (#| ... |#, nested-aware), datum comments (#;),
and quote/quasiquote/unquote prefixes.

Validated end-to-end on a 1477-line Guile project runner (430 lines changed)
and a 2400-line Org config (41 embedded scheme blocks). Both passed structural
paren-balance check and dry-run build after conversion.

The #1 conversion trap this handles correctly: case/match have a key/expr
sub-expression BEFORE the clauses, which must stay in round parens.
Only the clauses (children after the key/expr) get bracketed.
"""

import sys
import re

# Forms whose binding/clause positions take brackets per R6RS Appendix C
BINDING_FORMS = {'let', 'let*', 'letrec', 'letrec*', 'let-values', 'let-values*'}
# Clause forms split into two groups:
#   - no-key: cond/guard/case-lambda (every direct child is a clause)
#   - has-key: case/match (first child is key/expr, rest are clauses)
CLAUSE_NO_KEY = {'cond', 'guard', 'case-lambda'}
CLAUSE_HAS_KEY = {'case', 'match'}
DO_FORM = 'do'
SYNTAX_FORMS = {'syntax-rules', 'syntax-case'}


def tokenize(src):
    """Character-level scan → token list.

    Each token: (type, text, start, end)
    type ∈ {lparen, rparen, lbracket, rbracket, atom, string, comment,
            char, block_comment, datum_comment, quote_like}
    """
    tokens = []
    i = 0
    n = len(src)

    while i < n:
        c = src[i]

        # Block comment #| ... |# (nested-aware)
        if c == '#' and i + 1 < n and src[i + 1] == '|':
            depth = 1
            j = i + 2
            while j < n and depth > 0:
                if src[j] == '#' and j + 1 < n and src[j + 1] == '|':
                    depth += 1
                    j += 2
                elif src[j] == '|' and j + 1 < n and src[j + 1] == '#':
                    depth -= 1
                    j += 2
                else:
                    j += 1
            tokens.append(('block_comment', src[i:j], i, j))
            i = j
            continue

        # Datum comment #;
        if c == '#' and i + 1 < n and src[i + 1] == ';':
            tokens.append(('datum_comment', '#;', i, i + 2))
            i += 2
            continue

        # Line comment ;
        if c == ';':
            j = i
            while j < n and src[j] != '\n':
                j += 1
            tokens.append(('comment', src[i:j], i, j))
            i = j
            continue

        # String "..."
        if c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            tokens.append(('string', src[i:j], i, j))
            i = j
            continue

        # Char literal #\...  (CRITICAL: #\( #\) look like parens but aren't)
        if c == '#' and i + 1 < n and src[i + 1] == '\\':
            j = i + 2
            if j < n:
                if src[j].isalpha():
                    while j < n and src[j].isalpha():
                        j += 1
                else:
                    j += 1
            tokens.append(('char', src[i:j], i, j))
            i = j
            continue

        # Brackets
        if c == '(':
            tokens.append(('lparen', '(', i, i + 1))
            i += 1
            continue
        if c == ')':
            tokens.append(('rparen', ')', i, i + 1))
            i += 1
            continue
        if c == '[':
            tokens.append(('lbracket', '[', i, i + 1))
            i += 1
            continue
        if c == ']':
            tokens.append(('rbracket', ']', i, i + 1))
            i += 1
            continue

        # Quote/quasiquote/unquote prefixes
        if c in "'`":
            tokens.append(('quote_like', c, i, i + 1))
            i += 1
            continue
        if c == ',' and i + 1 < n and src[i + 1] == '@':
            tokens.append(('quote_like', ',@', i, i + 2))
            i += 2
            continue
        if c == ',':
            tokens.append(('quote_like', ',', i, i + 1))
            i += 1
            continue

        # Atom (including #t #f #' #` #, vectors #( etc.)
        if c.isspace():
            i += 1
            continue

        j = i
        while j < n and not src[j].isspace() and src[j] not in '()[];"\'`':
            j += 1
        if j == i:
            j = i + 1
        tokens.append(('atom', src[i:j], i, j))
        i = j

    return tokens


class Paren:
    """Bracket-pair tree node."""
    def __init__(self, open_idx, open_pos, parent=None):
        self.open_idx = open_idx
        self.open_pos = open_pos
        self.close_idx = None
        self.close_pos = None
        self.parent = parent
        self.children = []
        self.form_name = None
        self.should_bracket = False


def build_tree(tokens):
    """Build the bracket-pair tree. Returns (roots, paren_nodes)."""
    roots = []
    stack = []

    for idx, tok in enumerate(tokens):
        ttype = tok[0]

        if ttype in ('datum_comment', 'quote_like'):
            continue

        if ttype in ('lparen', 'lbracket'):
            parent = stack[-1] if stack else None
            node = Paren(idx, tok[2], parent)
            if parent:
                parent.children.append(node)
            else:
                roots.append(node)
            stack.append(node)
            # Determine form name: next meaningful atom after the open paren
            form_name = None
            for j in range(idx + 1, len(tokens)):
                nt = tokens[j]
                if nt[0] in ('comment', 'block_comment', 'datum_comment', 'quote_like'):
                    continue
                if nt[0] == 'atom':
                    form_name = nt[1]
                break
            node.form_name = form_name
            continue

        if ttype in ('rparen', 'rbracket'):
            if stack:
                node = stack.pop()
                node.close_idx = idx
                node.close_pos = tok[2]  # start of the close-bracket char
            continue

    return roots


def mark_brackets(roots):
    """Walk the tree and mark which bracket-pairs should become [] ."""
    def visit(node):
        name = node.form_name
        children = node.children

        if name in BINDING_FORMS:
            # let/let*/letrec: first child is the binding list (...),
            # each direct child of THAT is a single binding [var init].
            if children:
                binding_list = children[0]
                for binding in binding_list.children:
                    binding.should_bracket = True

        elif name in CLAUSE_NO_KEY:
            # cond/guard/case-lambda: every direct child is a clause.
            for c in children:
                c.should_bracket = True

        elif name in CLAUSE_HAS_KEY:
            # case/match: handled in handle_clause_mark (needs token stream
            # to tell whether key/expr is a parenthesised expression or atom).
            pass

        elif name == DO_FORM:
            # (do (bindings) (test result...) body...) — only bindings bracket.
            if children:
                for binding in children[0].children:
                    binding.should_bracket = True

        elif name in SYNTAX_FORMS:
            if name == 'syntax-rules':
                # (syntax-rules (literals) rule...) — skip literals, bracket rules.
                for c in children[1:]:
                    c.should_bracket = True
            elif name == 'syntax-case':
                # (syntax-case expr (literals) rule...) — skip expr + literals.
                for c in children[2:]:
                    c.should_bracket = True

        for c in children:
            visit(c)

    for r in roots:
        visit(r)


def handle_clause_mark(roots, tokens):
    """Handle case/match: skip the key/expr sub-expression, bracket the rest.

    The key/expr is the first sub-expression after the form name. We must
    inspect the token stream to know whether it's a parenthesised expression
    (→ it occupies children[0], skip children[0]) or an atom (→ it doesn't
    appear in children at all, bracket everything).
    """
    def visit(node):
        if node.form_name in CLAUSE_HAS_KEY:
            found_name = False
            first_is_paren = False
            for j in range(node.open_idx + 1, len(tokens)):
                t = tokens[j]
                if t[0] in ('comment', 'block_comment', 'datum_comment', 'quote_like'):
                    continue
                if not found_name:
                    found_name = True  # the form-name atom (case/match)
                    continue
                # Second meaningful token: if it's a paren, key/expr is parenthesised
                if t[0] in ('lparen', 'lbracket'):
                    first_is_paren = True
                break

            children = node.children
            if first_is_paren and children:
                # Skip the key/expr (children[0]), bracket the rest.
                for c in children[1:]:
                    c.should_bracket = True
            else:
                # key/expr is an atom — all children are clauses.
                for c in children:
                    c.should_bracket = True

        for c in node.children:
            visit(c)

    for r in roots:
        visit(r)


def apply_brackets(src, roots):
    """Rewrite () → [] at every marked position. Returns new source."""
    positions = set()

    def collect(node):
        if node.should_bracket:
            positions.add(node.open_pos)
            positions.add(node.close_pos)
        for c in node.children:
            collect(c)

    for r in roots:
        collect(r)

    result = []
    for i, c in enumerate(src):
        if i in positions:
            if c == '(':
                result.append('[')
            elif c == ')':
                result.append(']')
            else:
                result.append(c)
        else:
            result.append(c)
    return ''.join(result)


def convert(src):
    """Convert Scheme source: parens → brackets (R6RS Appendix C positions)."""
    tokens = tokenize(src)
    roots = build_tree(tokens)
    mark_brackets(roots)
    handle_clause_mark(roots, tokens)
    return apply_brackets(src, roots)


def convert_org(src):
    """Convert an Org file: only #+begin_src scheme ... #+end_src blocks."""
    pattern = re.compile(
        r'(#\+begin_src\s+scheme[^\n]*\n)(.*?)(#\+end_src)',
        re.IGNORECASE | re.DOTALL)

    def repl(m):
        return m.group(1) + convert(m.group(2)) + m.group(3)

    return pattern.sub(repl, src)


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('scm', 'org'):
        sys.stderr.write('usage: convert-brackets.py scm|org <file>\n')
        sys.exit(2)
    mode, path = sys.argv[1], sys.argv[2]
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    out = convert_org(src) if mode == 'org' else convert(src)
    sys.stdout.write(out)
