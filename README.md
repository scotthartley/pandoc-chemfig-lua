# pandoc-chemfig

A Pandoc Lua filter for figure and image processing in Markdown documents.
Designed for scientific writing where custom float environments (scheme,
chart, etc.) and cross-referencing are needed.

## Features

- Alternate LaTeX float environments (scheme, chart, etc.) via the image class
  attribute.
- Cross-referencing: `@id` citations are replaced with sequential numbers
  (non-LaTeX) or `\ref{}` commands (LaTeX).
- `wrapfig`/`wrapfloat` support via the `wwidth` and `wpos` image attributes.
- Float placement control via the `lpos` attribute.
- LaTeX type suffix (`lts`) support for starred environments (e.g. `scheme*`).
- Custom caption formats in non-LaTeX via metadata keys (e.g.
  `scheme_caption_format`).
- Document-wide `wrapfloat` kill switch via the `disable_pandoc_chemfig_wrap`
  metadata flag.

## Requirements

- Pandoc 3.0 or later (uses the Figure AST node introduced in Pandoc 3).

## Usage

Run with pandoc's `--lua-filter` option:

```sh
pandoc input.md --lua-filter pandoc-chemfig.lua -o output.pdf
```

Markdown source example:

```markdown
![My caption](image.png){#s:1 .scheme wwidth=0.4in wpos=r}

As shown in Scheme @s:1, the reaction proceeds via...
```

## Image Attributes

| Attribute | Description | Example |
|-----------|-------------|---------|
| **Class** (required) | The first class on the image determines the float environment name. | `.scheme`, `.chart` |
| **Identifier** (required) | Used for `\label` in LaTeX and for cross-referencing. | `#s:1` |
| `wwidth` | Width for wrapfloat. Setting this triggers wrapping. `0in` fits to width of image. | `wwidth=0.4in` |
| `wpos` | Position for wrapfloat. Defaults to `r` (right). | `wpos=l` |
| `lpos` | Explicit float placement specifier. Mutually exclusive with `wwidth`/`wpos`; wrapping takes priority if both are set. | `lpos=htbp` |
| `width` | Image width passed to `\includegraphics`. Percentages are relative to `\linewidth`; `px` or unitless values are converted at 96 dpi; other units (`in`, `cm`, `mm`, `pt`, ...) pass through. Non-LaTeX formats use pandoc's normal handling. | `width=3.5in`, `width=50%` |
| `height` | Image height passed to `\includegraphics`. Percentages are relative to `\textheight`. If both `width` and `height` are set, `keepaspectratio` is added. | `height=2in` |
| `lts` | LaTeX type suffix appended to the float environment name. | `lts=*` produces `\begin{scheme*}` |

## Caption Format Overrides

Custom caption formats can be set in the document metadata using keys
of the form `<class>_caption_format`. The `#` character is replaced with
the sequential figure number.

Example YAML front matter:

```yaml
---
scheme_caption_format: "*Scheme #:*"
---
```

The default format for any class is bold with a period, e.g. **Scheme #.**

## Document Metadata Options

### Disable wrapfloat wrapping

Setting the `disable_pandoc_chemfig_wrap` metadata flag forces every figure to
normal LaTeX float placement, ignoring `wwidth`/`wpos` document-wide. Figures
with `lpos` still honor it (`\begin{scheme}[htbp]…`); others fall back to
LaTeX's default placement (`\begin{scheme}…`). Non-LaTeX output is unaffected.

Via the command line:

```sh
pandoc input.md --lua-filter pandoc-chemfig.lua \
    --metadata=disable_pandoc_chemfig_wrap -o output.pdf
```

Via YAML front matter:

```yaml
---
disable_pandoc_chemfig_wrap: true
---
```

## Acknowledgements

Developed with the help of Claude Code.

## License

MIT License. See [LICENSE](LICENSE) for details.
