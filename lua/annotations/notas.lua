local M = {}

-- ═══════════════════════════════════════════════════════════════════
-- Notas de texto para las anotaciones (parte nativa de este plugin)
--
-- La nota es un campo más de la anotación (`ann.note`), así que:
--   * muere con ella (poda de stale, clear, borrado),
--   * se guarda con el mismo JSON (annotations.json),
--   * y al hacer UNDO de las anotaciones, las notas reviven también.
--
-- En la fusión (merge) las notas se pierden: `merge.union` construye la
-- anotación fusionada campo por campo y suelta `note`; main.lua avisa
-- antes de perderlas.
-- ═══════════════════════════════════════════════════════════════════

local DEFAULTS = {
	-- La vista previa flotante muestra como máximo este número de caracteres
	-- de la nota; si se pasa, ofrece abrirla completa.
	max_chars = 240,
	-- Vista previa automática al quedarse quieto (CursorHold) sobre una
	-- anotación con nota.
	auto_hover = true,
}

M.options = DEFAULTS

-- ------------------------------------------------------------
-- Anotación bajo el cursor
-- ------------------------------------------------------------

function M.find_at(anns, lnum, col)
	for _, a in ipairs(anns) do
		if lnum == a.beg_line and lnum == a.end_line then
			if col >= a.beg_col and col <= a.end_col then
				return a
			end
		elseif lnum == a.beg_line then
			if col >= a.beg_col then
				return a
			end
		elseif lnum == a.end_line then
			if col <= a.end_col then
				return a
			end
		elseif lnum > a.beg_line and lnum < a.end_line then
			return a
		end
	end
	return nil
end

-- Versión tolerante para comandos EXPLÍCITOS: si el cursor está en una línea
-- que cruza una anotación pero fuera de sus columnas frontera (un caracter
-- antes del inicio, uno después del fin), cuenta igual — visualmente sí estás
-- "sobre lo resaltado". Con varias, gana la de columna más cercana. El hover
-- automático usa find_at (estricto) para no asustar con popups fantasma.
local function find_fuzzy(anns, lnum, col)
	local exacta = M.find_at(anns, lnum, col)
	if exacta then
		return exacta
	end
	local mejor, mejor_d = nil, math.huge
	for _, a in ipairs(anns) do
		if lnum >= a.beg_line and lnum <= a.end_line then
			local d = 0
			if lnum == a.beg_line and col < a.beg_col then
				d = a.beg_col - col
			end
			if lnum == a.end_line and col > a.end_col then
				d = math.max(d, col - a.end_col)
			end
			if d < mejor_d then
				mejor, mejor_d = a, d
			end
		end
	end
	return mejor
end

local function cursor_annotation()
	local filepath = vim.fn.expand("%:p")
	if filepath == "" then
		return nil, nil
	end
	local anns = require("annotations.storage").get_annotations_for_file(filepath)
	local ann = M.find_at(anns, vim.fn.line("."), vim.fn.col("."))
	return ann, filepath
end

-- Escribe/cambia/borra la nota de una anotación y persiste. Nota vacía = borrar.
local function set_note(filepath, ann, texto)
	texto = texto and texto:gsub("%s+$", "") or ""
	local anns = require("annotations.storage").get_annotations_for_file(filepath)
	local objetivo = string.format("%d:%d:%d:%d:%s", ann.beg_line, ann.beg_col, ann.end_line, ann.end_col, ann.text)
	for _, a in ipairs(anns) do
		local k = string.format("%d:%d:%d:%d:%s", a.beg_line, a.beg_col, a.end_line, a.end_col, a.text)
		if k == objetivo then
			a.note = texto ~= "" and texto or nil
			require("annotations.storage").save_annotations_for_file(filepath, anns)
			return
		end
	end
end

-- ------------------------------------------------------------
-- UI: preview flotante + ventana grande estilo :h
-- ------------------------------------------------------------

local preview_win = nil

local function close_preview()
	if preview_win and vim.api.nvim_win_is_valid(preview_win) then
		vim.api.nvim_win_close(preview_win, true)
	end
	preview_win = nil
	pcall(vim.api.nvim_clear_autocmds, { group = "AnnotationsNotasPreview" })
end

-- Float anclado al cursor con la nota truncada a max_chars; si se truncó,
-- ofrece abrirla completa con el comando/tecla de lectura.
local function show_preview(note)
	close_preview()
	local truncada = vim.fn.strchars(note) > M.options.max_chars
	local texto = note
	if truncada then
		texto = vim.fn.strcharpart(note, 0, M.options.max_chars) .. "…"
	end
	local lineas = vim.split(texto, "\n", { plain = true })
	if truncada then
		vim.list_extend(lineas, { "", "… <leader>ho = nota completa" })
	end

	local ancho = 30
	for _, l in ipairs(lineas) do
		ancho = math.max(ancho, math.min(vim.fn.strdisplaywidth(l) + 2, 72))
	end
	local alto = math.min(#lineas, 12)
	-- Ancla inteligente: en la mitad baja de la pantalla, abre hacia arriba.
	local anchor = (vim.fn.winline() > math.floor(vim.o.lines / 2)) and "SW" or "NW"

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.b[buf].annotations_notes_ui = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lineas)

	preview_win = vim.api.nvim_open_win(buf, false, {
		relative = "cursor",
		anchor = anchor,
		row = anchor == "SW" and -1 or 1,
		col = 0,
		width = ancho,
		height = alto,
		style = "minimal",
		border = "rounded",
		focusable = false,
		title = " nota ",
		title_pos = "left",
	})
	vim.api.nvim_create_augroup("AnnotationsNotasPreview", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
		group = "AnnotationsNotasPreview",
		buffer = vim.api.nvim_get_current_buf(),
		callback = close_preview,
	})
end

-- Ventana grande estilo :h: un SPLIT real (no flotante), arriba y a lo ancho,
-- dejando tu buffer como una tira abajo — como la ayuda. Al ser ventana de
-- verdad, dentro funcionan búsquedas, marcas, todo vim.
-- editable=true la vuelve scratch de escritura con teclas de guardar.
local function open_big_window(texto, editable, on_save)
	-- Recordar de dónde venimos: al cerrar hay que volver EXPLÍCITAMENTE aquí,
	-- porque nvim elige la ventana "anterior" con sus propios criterios y con
	-- varias ventanas abiertas te puede mandar a otro buffer.
	local win_origen = vim.api.nvim_get_current_win()
	local lineas = vim.split(texto == "" and " " or texto, "\n", { plain = true })

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe" -- al cerrar la ventana, el buffer muere solo
	vim.b[buf].annotations_notes_ui = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lineas)
	vim.bo[buf].modifiable = editable
	vim.bo[buf].modified = false -- abrir no cuenta como "modificada"

	vim.cmd("topleft split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	local alto = math.min(#lineas + 1, vim.o.lines - vim.o.cmdheight - 2)
	vim.api.nvim_win_set_height(win, math.max(alto, 4))
	vim.wo[win].wrap = true
	vim.wo[win].number = true -- como en la ayuda
	vim.wo[win].spell = true -- las notas son prosa
	vim.bo[buf].spelllang = "es,en" -- (spelllang es buffer-local)
	vim.wo[win].winbar = editable and " nota — <C-s> guardar · q salir sin guardar "
		or " nota — q para cerrar "

	local function volver_al_origen()
		if vim.api.nvim_win_is_valid(win_origen) then
			vim.api.nvim_set_current_win(win_origen)
		end
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end

	local function cerrar()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		volver_al_origen()
	end

	-- Red de seguridad: si cierras la ventana por tu cuenta (:q, <C-w>c),
	-- también vuelve al origen; y el buffer scratch muere solo (bufhidden=wipe).
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win_origen) then
				vim.api.nvim_set_current_win(win_origen)
			end
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end,
	})

	if editable then
		local function guardar()
			-- Salir de insert ANTES de cerrar (nvim no permite cerrar ventanas
			-- desde el modo insert).
			vim.cmd("stopinsert")
			local contenido = table.concat(
				vim.api.nvim_buf_get_lines(buf, 0, -1, false),
				"\n"
			):gsub("%s+$", "")
			cerrar()
			on_save(contenido)
		end
		vim.keymap.set({ "n", "i" }, "<C-s>", guardar, { buffer = buf, desc = "Guardar nota y cerrar" })
		local function salir_sin_guardar()
			if vim.bo[buf].modified then
				vim.ui.select({ "Descartar cambios", "Seguir editando" }, {
					prompt = "Nota modificada: ¿salir sin guardar?",
				}, function(opcion)
					if opcion == "Descartar cambios" then
						cerrar()
					end
				end)
			else
				cerrar()
			end
		end
		vim.keymap.set("n", "q", salir_sin_guardar, { buffer = buf, desc = "Salir sin guardar" })
		vim.keymap.set("n", "<Esc>", salir_sin_guardar, { buffer = buf, desc = "Salir sin guardar" })
	else
		vim.keymap.set("n", "q", cerrar, { buffer = buf, desc = "Cerrar nota" })
		vim.keymap.set("n", "<Esc>", cerrar, { buffer = buf, desc = "Cerrar nota" })
	end
end

-- ------------------------------------------------------------
-- Acciones
-- ------------------------------------------------------------

-- Escribir/editar la nota de la anotación bajo el cursor.
function M.edit()
	local ann, filepath = cursor_annotation()
	if not ann then
		vim.notify("annotations: no hay anotación bajo el cursor", vim.log.levels.WARN)
		return
	end
	local nota_actual = ann.note or ""

	open_big_window(nota_actual, true, function(contenido)
		-- Al guardar, verifica que la anotación siga viva (pudo morir mientras
		-- editabas). Las notas viven y mueren con su anotación.
		local sigue_viva = false
		local anns = require("annotations.storage").get_annotations_for_file(filepath)
		local objetivo = string.format(
			"%d:%d:%d:%d:%s",
			ann.beg_line, ann.beg_col, ann.end_line, ann.end_col, ann.text
		)
		for _, a in ipairs(anns) do
			local k = string.format("%d:%d:%d:%d:%s", a.beg_line, a.beg_col, a.end_line, a.end_col, a.text)
			if k == objetivo then
				sigue_viva = true
				break
			end
		end
		if not sigue_viva then
			vim.notify("annotations: la anotación ya no existe; nota descartada", vim.log.levels.WARN)
			return
		end
		set_note(filepath, ann, contenido)
		if contenido == "" then
			vim.notify("annotations: nota eliminada")
		else
			vim.notify("annotations: nota guardada")
		end
	end)
end

-- Leer la nota completa (ventana tipo :h).
function M.open()
	local ann, filepath = cursor_annotation()
	if not ann or not ann.note then
		vim.notify("annotations: no hay nota bajo el cursor", vim.log.levels.INFO)
		return
	end
	open_big_window(ann.note, false)
end

-- Vista previa automática (CursorHold).
local function on_hover()
	if not M.options.auto_hover then
		return
	end
	if preview_win then
		return
	end
	if vim.bo.buftype ~= "" or vim.b.annotations_notes_ui then
		return
	end
	local ann, filepath = cursor_annotation()
	if ann and ann.note then
		show_preview(ann.note)
	end
end

-- ------------------------------------------------------------
-- Importación del legado (antes de que la nota fuera campo nativo)
-- ------------------------------------------------------------

-- Lee las notas del formato viejo (annotations-notes.json con llaves
-- posición+texto) y las incrusta en las anotaciones vivas de annotations.json.
-- Hace respaldos `.bak-legado` antes de tocar algo. Idempotente.
function M.importar_legado()
	local data_dir = vim.fn.stdpath("data")
	local legado = data_dir .. "/annotations-notes.json"
	local storage_path = require("annotations").options.storage_path
		or (data_dir .. "/annotations.json")

	if vim.fn.filereadable(legado) == 0 then
		vim.notify("annotations: no hay archivo legado de notas (" .. legado .. ")", vim.log.levels.INFO)
		return
	end

	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(legado), "\n"))
	end)
	if not ok or type(data) ~= "table" then
		vim.notify("annotations: legado ilegible, no se importó nada", vim.log.levels.WARN)
		return
	end

	-- Respaldos antes de escribir
	for _, ruta in ipairs({ legado, storage_path }) do
		if vim.fn.filereadable(ruta) == 1 then
			vim.fn.writefile(vim.fn.readfile(ruta), ruta .. ".bak-legado")
		end
	end

	local storage = require("annotations.storage")
	local importadas, huerfanas = 0, 0

	for filepath, notas in pairs(data) do
		local anns = storage.get_annotations_for_file(filepath)
		if #anns == 0 then
			huerfanas = huerfanas + #notas
		else
			for _, n in ipairs(notas) do
				local objetivo = string.format(
					"%d:%d:%d:%d:%s",
					n.k[1], n.k[2], n.k[3], n.k[4], n.k[5]
				)
				local encontrada = false
				for _, a in ipairs(anns) do
					local k = string.format("%d:%d:%d:%d:%s", a.beg_line, a.beg_col, a.end_line, a.end_col, a.text)
					if k == objetivo then
						if n.note and n.note ~= "" and not a.note then
							a.note = n.note
							importadas = importadas + 1
						end
						encontrada = true
						break
					end
				end
				if not encontrada then
					huerfanas = huerfanas + 1
				end
			end
			storage.save_annotations_for_file(filepath, anns)
		end
	end

	vim.notify(
		("annotations: legado importado — %d nota(s) incrustada(s), %d huérfana(s) descartada(s). Respaldos en *.bak-legado")
			:format(importadas, huerfanas)
	)
end

-- ------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.options, DEFAULTS, opts or {})

	vim.api.nvim_create_user_command("AnnotationNote", function()
		M.edit()
	end, { desc = "Escribir/editar la nota de la anotación bajo el cursor" })

	vim.api.nvim_create_user_command("AnnotationNoteOpen", function()
		M.open()
	end, { desc = "Leer la nota completa de la anotación bajo el cursor" })

	vim.api.nvim_create_user_command("AnnotationImportarLegado", function()
		M.importar_legado()
	end, { desc = "Importar notas del formato viejo (annotations-notes.json)" })

	vim.keymap.set("n", "<leader>hn", M.edit, { desc = "Nota de la anotación (editar)" })
	vim.keymap.set("n", "<leader>ho", M.open, { desc = "Nota de la anotación (leer completa)" })

	local group = vim.api.nvim_create_augroup("AnnotationsNotas", { clear = true })
	vim.api.nvim_create_autocmd("CursorHold", {
		group = group,
		pattern = "*",
		callback = on_hover,
	})
end

return M
