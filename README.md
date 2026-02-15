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

## Acknowledgements

Developed with the help of Claude Code.

## License

MIT License. See [LICENSE](LICENSE) for details.
