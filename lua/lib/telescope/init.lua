local pickers = require("telescope.pickers")
local telescope_actions = require("telescope.actions")
local conf = require("telescope.config").values
local utils = require("lib.utils")
local previewers = require("telescope.previewers")
local putils = require("telescope.previewers.utils")

-- Show the real terminal buffer in Telescope's preview window to preserve colors
local termbuf_previewer = previewers.new_buffer_previewer({
	title = "Terminal",
	keep_last_buf = true, -- don't let touch the terminal buffer (just in case)
	define_preview = function(self, entry)
		local term = entry.value
		local bufnr = term and term.bufnr

		if not (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal") then
			return putils.set_preview_message(self.state.bufnr, "No terminal buffer")
		end

		vim.schedule(function()
			vim.api.nvim_win_set_buf(self.state.winid, bufnr)
			self.state.bufnr = bufnr
			self.state.bufname = vim.api.nvim_buf_get_name(bufnr)
		end)
	end,
})

--- Create autocommand to enter insert mode when the cursor leaves the telescope buffer.
--- Useful for actions that are called with exit_on_action set to false b/c it allows the user
--- to manually exit telescope but still automatically enter insert mode in the terminal buffer
--- @param picker table The telescope picker object.
local function telescope_leave_autocmd(picker)
	vim.api.nvim_create_augroup("InsertOnPickerLeave", {})
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = picker.prompt_bufnr,
		group = "InsertOnPickerLeave",
		nested = true,
		once = true,
		callback = function()
			local win_is_valid = vim.api.nvim_win_is_valid(picker.original_win_id)
			if win_is_valid then
				local picker_orig_win_bufnr = vim.fn.winbufnr(picker.original_win_id)
				local buftype = vim.api.nvim_buf_get_option(picker_orig_win_bufnr, "filetype")
				if buftype == "toggleterm" then
					utils.start_insert_mode()
				end
			end
		end,
	})
end

local M = {}

--- Entry point. Opens a telescope picker.
--- @param opts table The options for the picker.
M.open = function(opts)
	local config = require("config").options
	-- set origin window, which will need to be retrieved in some actions (actions/init.lua)
	require("toggleterm.ui").set_origin_window()

	local picker = pickers.new(opts, {
		prompt_title = config.titles.prompt,
		results_title = config.display_mappings and utils.format_results_title(config.mappings)
			or config.titles.results,
		preview_title = config.titles.preview,
		previewer = termbuf_previewer,
		finder = utils.create_finder(),
		sorter = conf.generic_sorter(opts),
		attach_mappings = function(prompt_bufnr, map)
			local mappings = config.mappings
			for mode, mode_mappings in pairs(mappings) do
				for keybind, action_tbl in pairs(mode_mappings) do
					if action_tbl ~= false then
						local action = action_tbl["action"]
						local exit_on_action = action_tbl["exit_on_action"]
						map(mode, keybind, function()
							action(prompt_bufnr, exit_on_action)
						end)
					end
				end
			end

			telescope_actions.select_default:replace(function() end)

			return true
		end,
	})
	picker:find()
	telescope_leave_autocmd(picker)
end
return M
