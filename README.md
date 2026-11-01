# annotations-notes.nvim

Annotate (<mark>highlight</mark>) visually selected text in Neovim — **y ahora escribe notas sobre cada anotación**.

> **Este fork** es mantenido por **Edwardo Malta** y añade una capa de notas al
> plugin original de [celsobenedetti](https://github.com/celsobenedetti/annotations.nvim):
> escribe una nota sobre un pasaje resaltado, léela en una ventana tipo `:h`,
> o asómate a ella con una vista previa flotante.
>
> **Procedencia y licencia**: el motor de resaltado deriva de
> [high-str.nvim](https://github.com/pocco81/high-str.nvim) (GPL-3.0) vía
> annotations.nvim, por lo que **este paquete se distribuye bajo GPL-3.0**
> (ver [LICENSE](LICENSE)). La capa de notas y su interfaz son desarrollo propio.

<details>
<summary>What are annotations?</summary>

Really, they are actually _"highlights"_, as in _<mark>"highlighted text"</mark>_.

I call them _"annotations"_ since _"highlights"_ mean something else in Neovim (`:h hi`).

</details>

## features

- Annotate visually selected text
  - if current selection overlaps one or more existing annotations, merge them into one.
  - if current selection is wholy contained within an existing annotation, remove it instead.
- Persist annotations to `stdpath("data")/annotations.json` with text, position, and file path.
- **Notas de texto** sobre cada anotación (`AnnotationNote` / `AnnotationNoteOpen`):
  - viven en el mismo JSON — mueren con su anotación y reviven con `AnnotationsUndo`.
  - vista previa flotante automática (CursorHold), truncada a `max_chars`.
  - lectura/edición en ventana tipo `:h` (`<C-s>` guarda, `q` sale).
  - al fusionar anotaciones con notas, se avisa antes de perderlas.
  - migración automática del formato viejo de notas (`AnnotationImportarLegado`).
- Auto-restore highlights when opening a file 
    - verifies text+position match, prunes stale annotations.
- Sidebar listing all annotations for the current buffer (`AnnotationsSidebar`), multi-line support with thin separator, `<CR>` jumps to source.
- Undo the last annotation action (add/remove/merge/clear) per file (`AnnotationsUndo`).
- Send all annotations for the current file to the quickfix list (`AnnotationsQuickfix`).
- Toggle highlight visibility without altering stored annotations (`AnnotationsToggle`).
- Clear all annotations for the current file (`AnnotationsClear`).
- [nvim-mini/mini.ai](https://github.com/nvim-mini/mini.ai) integration: custom _annotations_ (`h`) textobject. Auto-detected if `mini.ai` is installed.

## setup

See [init.lua](lua/annotations/init.lua) for configuration options.

```lua

{
    'edwardomalta/annotations-notes.nvim',
    config = function()
        require("annotations").setup({
            notes = {
                max_chars = 240, -- truncado de la vista previa flotante
                auto_hover = true, -- preview automática con CursorHold
            },
        })
    end,
    keys = {
        { '<leader>h', ':<c-u>AnnotationsAdd<CR>', mode = 'x' },
    },
}
```

## usage

- `AnnotationsAdd` to add an annotation to the current buffer.
- `AnnotationsToggle` to toggle the visibility of annotations.
- `AnnotationsClear` to clear all annotations for the current buffer.
- `AnnotationsQuickfix` to send all annotations for the current buffer to the quickfix list.
- `AnnotationsSidebar` to open a sidebar listing all annotations for the current buffer.
- `AnnotationsUndo` to undo the last annotation action (add/remove/merge/clear) for the current buffer.
- `AnnotationNote` to write/edit the note of the annotation under the cursor.
- `AnnotationNoteOpen` to read the full note (help-style window, `q` closes).
- `AnnotationImportarLegado` to import notes from the old `annotations-notes.json` format (one-time, idempotent).

### notas — atajos sugeridos

| Tecla | Acción |
|---|---|
| `<leader>hn` | escribir/editar la nota de la anotación bajo el cursor |
| `<leader>ho` | leer la nota completa (ventana tipo `:h`) |
| CursorHold | vista previa flotante de la nota (si `auto_hover`) |

Estos atajos se definen en `setup()`; cada quien puede remapearlos.

## créditos y procedencia

- [celsobenedetti/annotations.nvim](https://github.com/celsobenedetti/annotations.nvim) — el plugin base y todas las ideas centrales. Este fork existe gracias a él.
- [pocco81/high-str.nvim](https://github.com/pocco81/high-str.nvim) — la implementación de resaltado originalmente derivada de aquí (GPL-3.0), de lo que hereda la licencia de este paquete.
- [stevearc/aerial.nvim](https://github.com/stevearc/aerial.nvim) — referencia para la implementación del sidebar.

## licencia

[GPL-3.0](LICENSE) — heredada de high-str.nvim vía annotations.nvim.
