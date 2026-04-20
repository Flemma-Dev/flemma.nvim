---
"@flemma-dev/flemma.nvim": patch
---

Fixed tool-result previews vanishing at `conceallevel>=1`. Tree-sitter's markdown query sets `conceal_lines = ""` on fenced-code delimiter lines, so anchoring virtual-line extmarks on the opening fence caused them to be hidden along with the delimiter. Now the virt_line anchors on the blank line between the `**Tool Result:**` header and the opening fence when conceal is active, keeping the preview visible under the default `editing.conceal = "2nv"`. The original inside-the-fence anchor is preserved at `conceallevel=0`.
