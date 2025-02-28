/* Window.vala
 *
 * Copyright 2021 Gleb Smirnov <glebsmirnov0708@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


namespace TextPieces {

    const uint NOTIFICATION_HIDE_TIMEOUT = 2000;

    [GtkTemplate (ui = "/com/github/liferooter/textpieces/ui/Window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] unowned Gtk.ListBox search_listbox;
        [GtkChild] unowned Gtk.SearchEntry search_entry;
        [GtkChild] unowned Gtk.Stack search_stack;
        [GtkChild] unowned Gtk.Revealer notification_revealer;
        [GtkChild] unowned Gtk.Revealer arguments_revealer;
        [GtkChild] unowned Gtk.Label notification_label;
        [GtkChild] unowned Gtk.Image tool_icon;
        [GtkChild] unowned Gtk.Label tool_label;
        [GtkChild] unowned Gtk.ToggleButton tool_button;
        [GtkChild] unowned Gtk.SourceView editor;
        [GtkChild] unowned Gtk.Viewport search_viewport;
        [GtkChild] unowned Gtk.Box arguments_box;

        string DEFAULT_TOOL_LABEL;
        string DEFAULT_TOOL_ICON;

        Gtk.SortListModel search_list;
        Gtk.Sorter search_sorter;
        Gtk.Filter search_filter;

        uint? notification_hide_source = null;

        Tool selected_tool = null;

        ToolsController tools {
            get {
                return ((TextPieces.Application) application).tools;
            }
        }

        private const ActionEntry[] ACTION_ENTRIES = {
            { "apply", action_apply },
            { "preferences", action_preferences },
            { "about", action_about },
            { "copy", action_copy },
            { "tools-settings", action_tools_settings },
            { "hide-notification", hide_notification },
            { "toggle-search", action_toggle_search },
            { "escape", action_escape },
            { "save-as", action_save_as },
            { "load-file", action_load_file },
            { "jump-to-args", action_jump_to_args }
        };

        construct {
            // Load actions
            add_action_entries (ACTION_ENTRIES, this);

            ((SimpleAction) lookup_action ("apply")).set_enabled (false);

            tool_button.notify["active"].connect(() => {
                if (!tool_button.active)
                    editor.grab_focus ();
                else
                    search_viewport.vadjustment.set_value (0);
            });
            Idle.add (setup_tools);
            arguments_revealer.notify["child-revealed"].connect (() => {
                editor.bottom_margin = arguments_revealer.get_allocated_height ();
            });

            DEFAULT_TOOL_ICON = tool_icon.icon_name;
            DEFAULT_TOOL_LABEL = tool_label.label;
        }

        public bool setup_tools () {

            search_sorter = new Gtk.CustomSorter (
                (a, b) => tool_compare_func (a as Tool, b as Tool)
            );
            search_filter = new Gtk.CustomFilter (tool_filter_func);

            search_list = new Gtk.SortListModel (
                new Gtk.FilterListModel (
                    tools.all_tools,
                    search_filter
                ),
                search_sorter
            );

            search_listbox.bind_model (
                search_list,
                build_list_row
            );

            tools.delete_tool.connect_after ((tool) => {
                if (tool == selected_tool) {
                    selected_tool = null;
                    ((SimpleAction) lookup_action ("apply")).set_enabled (false);

                    tool_icon.icon_name = DEFAULT_TOOL_ICON;
                    tool_label.label = DEFAULT_TOOL_LABEL;

                    var children = arguments_box.observe_children ();
                    for (uint i = 0; i < children.get_n_items (); i++)
                        arguments_box.remove ((Gtk.Widget) children.get_item (i));

                    arguments_revealer.set_reveal_child (false);
                }
            });

            return Source.REMOVE;
        }

        void action_apply () {
            if (selected_tool == null)
                return;
            if (!editor.has_focus)
                editor.grab_focus ();

            var buffer = editor.buffer;
            var has_selection = buffer.has_selection;

            Gtk.TextIter start, end;

            if (has_selection)
                buffer.get_selection_bounds (out start, out end);
            else
                buffer.get_bounds (out start, out end);

            var start_offset = start.get_offset ();

            string[] args = {};
            var children = arguments_box.observe_children ();
            for (uint i = 0; i < children.get_n_items (); i++)
                args += ((Gtk.Entry) children.get_item (i)).get_text ();

            var result = selected_tool.apply (
                buffer.get_text (start, end, false),
                args
            );

            string result_text;

            if (result.stderr != null) {
                send_notification (result.stderr);
            }

            if (result.stdout != null) {
                result_text = result.stdout;
            } else {
                return;
            }

            var result_text_len = result_text.char_count ();

            buffer.begin_user_action ();

            buffer.@delete (ref start, ref end);
            buffer.insert (ref start, result_text, -1);

            buffer.end_user_action ();

            if (has_selection) {
                buffer.get_iter_at_offset (
                    out start,
                    start_offset
                );
                buffer.get_iter_at_offset (
                    out end,
                    start_offset + result_text_len
                );
                buffer.select_range (start, end);
            } else {
                buffer.get_start_iter (out start);
                buffer.place_cursor (start);
            }
        }

        void action_preferences () {
            var prefs = new Preferences () {
                transient_for = this,
                application = application
            };
            prefs.present ();
        }

        void action_about () {
            string[] AUTHORS = {"Gleb Smirnov <glebsmirnov0708@gmail.com>"};
            string[] ARTISTS = {"Tobias Bernard https://tobiasbernard.com"};

            Gtk.show_about_dialog (
                this,
                "program-name", _("Text Pieces"),
                "logo-icon-name", "com.github.liferooter.textpieces",
                "comments", _("Swiss knife of text transformations"),
                "version", Config.VERSION,
                "license-type", Gtk.License.GPL_3_0,
                "website", "https://gitlab.com/liferooter/textpieces",
                "artists", ARTISTS,
                "authors", AUTHORS,
                "translator-credits", _("translator-credits"),
                null
        );
        }

        void action_copy () {
            Gdk.Display.get_default ()
                       .get_clipboard ()
                       .set_text (editor.buffer.text);
            send_notification (_("Text is copied to clipboard"));
        }

        void action_tools_settings () {
            var prefs = new Preferences () {
                transient_for = this,
                application = application,
                focus_add_tool_button = true
            };
            prefs.present ();
        }

        void hide_notification () {
            clear_notification_hide_timeout ();
            notification_revealer.set_reveal_child (false);
        }

        int calculate_relevance (Tool tool) {
            var query = search_entry.text;
            var terms = query.split (" ");

            string[] fields = {
                tool.name.casefold (),
                tool.description.casefold (),
            };

            int[] min_match = {0, 0};

            int relevance = 0;

            foreach (var term in terms) {
                int i = 0;
                int match = 0;
                while (i < fields.length
                       && (match = fields[i].index_of (term, min_match[i])) == -1) {
                    i++;
                }
                if (i == fields.length)
                    return -1;

                relevance += match - min_match[i];

                min_match[i] = match + term.length;
            }

            if (min_match[0] == 0)
                relevance += fields[1].length + 1;

            return relevance;
        }

        bool tool_filter_func (Object item) {
            var tool = (Tool) item;

            return calculate_relevance (tool) != -1;
        }

        int tool_compare_func (Tool? a, Tool? b) {
            // Null-test
            if (a == null) {
                if (b == null)
                    return Gtk.Ordering.EQUAL;
                else
                    return Gtk.Ordering.SMALLER;
            } if (b == null) {
                if (a == null)
                    return Gtk.Ordering.EQUAL;
                else
                    return Gtk.Ordering.LARGER;
            }

            var a_rel = calculate_relevance (a);
            var b_rel = calculate_relevance (b);

            if (a_rel > b_rel)
                return Gtk.Ordering.LARGER;
            else if (a_rel < b_rel)
                return Gtk.Ordering.SMALLER;
            else // a_rel == b_rel
                return strcmp (a.name, b.name);
        }

        void send_notification (string text) {
            clear_notification_hide_timeout ();
            notification_label.set_label (text);
            notification_revealer.set_reveal_child (true);
            notification_hide_source = Timeout.add (
                NOTIFICATION_HIDE_TIMEOUT,
                () => {
                    hide_notification ();
                    return Source.REMOVE;
                }
            );
        }

        [GtkCallback]
        string get_page_name (bool search_enabled) {
            if (search_enabled) {
                return "search";
            } else {
                return "editor";
            }
        }

        [GtkCallback]
        void on_search_changed () {
            search_sorter.changed (Gtk.SorterChange.DIFFERENT);
            search_filter.changed (Gtk.FilterChange.DIFFERENT);

            search_stack.set_visible_child_name (
                search_list.get_n_items () == 0
                    ? "placeholder"
                    : "search"
            );
        }

        [GtkCallback]
        bool on_search_entry_key (uint keyval,
                                  uint keycode,
                                  Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Down) {
                var first_row = search_listbox.get_row_at_index (0);
                if (first_row != null) {
                    first_row.grab_focus ();
                    return true;
                }
            }
            return false;
        }

        [GtkCallback]
        bool on_search_listbox_key (uint keyval,
                                    uint keycode,
                                    Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Up) {
                var focus = this.focus_widget;
                if (focus.get_type () == typeof (Adw.ActionRow) &&
                    ((Adw.ActionRow) focus).get_index () == 0)
                {
                    search_entry.grab_focus ();
                    return true;
                }
            }
            return false;
        }

        [GtkCallback]
        void on_row_activated (Gtk.ListBoxRow row) {
            var tool = (Tool) search_list.get_item (row.get_index ());

            selected_tool = tool;

            tool_icon.icon_name = tool.icon;
            tool_label.label = tool.name;
            search_entry.stop_search ();

            var children = arguments_box.observe_children ();
            for (uint i = 0; i < children.get_n_items (); i++)
                arguments_box.remove ((Gtk.Widget) children.get_item (i));

            if (selected_tool.arguments.length == 0) {
                arguments_revealer.set_reveal_child (false);
            } else {
                arguments_revealer.set_reveal_child (true);
                for (var i = 0; i < selected_tool.arguments.length; i++) {
                    var entry = new Gtk.Entry () {
                        placeholder_text = selected_tool.arguments[i]
                    };
                    entry.activate.connect (() => {
                        move_focus (Gtk.DirectionType.TAB_FORWARD);
                    });
                    arguments_box.append (entry);
                }
            }

            ((SimpleAction) lookup_action ("apply")).set_enabled (true);
        }

        [GtkCallback]
        void on_search_activated () {
            var row = search_listbox.get_row_at_index (0);
            if (row != null)
                search_listbox.row_activated  (row);
        }

        void clear_notification_hide_timeout () {
            if (notification_hide_source != null) {
                Source.remove (notification_hide_source);
                notification_hide_source = null;
            }
        }

        void action_toggle_search () {
            tool_button.active = !tool_button.active;
            hide_notification ();
        }

        void action_escape () {
            if (notification_revealer.reveal_child == true)
                hide_notification ();
            else
                tool_button.set_active (false);
            editor.grab_focus ();
        }

        void action_save_as () {
            var file_chooser = new Gtk.FileChooserNative (
                _("Save to File"),
                this,
                Gtk.FileChooserAction.SAVE,
                null,
                null
            ) {
                transient_for = this,
                modal = true
            };
            file_chooser.response.connect (() => {
                var location = file_chooser.get_file ();
                if (location == null)
                    return;

                var file = new Gtk.SourceFile ();
                file.set_location (location);

                var saver = new Gtk.SourceFileSaver (
                    (Gtk.SourceBuffer) editor.buffer,
                    file
                );
                saver.save_async.begin (
                    Priority.HIGH,
                    null,
                    null,
                    (obj, res) => {
                        try {
                            saver.save_async.end (res);
                        } catch (Error e) {
                            var dialog = new Gtk.MessageDialog (
                                this,
                                Gtk.DialogFlags.MODAL
                                | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                Gtk.MessageType.WARNING,
                                Gtk.ButtonsType.CLOSE,
                                _("Can't save to file: %s"),
                                e.message
                            );
                            dialog.response.connect (dialog.destroy);
                            dialog.show ();
                        }
                    }
                );
            });
            file_chooser.show ();
        }

        void action_load_file () {
            var file_chooser = new Gtk.FileChooserNative (
                _("Load From File"),
                this,
                Gtk.FileChooserAction.OPEN,
                null,
                null
            ) {
                transient_for = this,
                modal = true
            };
            file_chooser.response.connect (() => {
                var location = file_chooser.get_file ();
                if (location == null)
                    return;

                var file = new Gtk.SourceFile ();
                file.set_location (location);

                var loader = new Gtk.SourceFileLoader (
                    (Gtk.SourceBuffer) editor.buffer,
                    file
                );
                loader.load_async.begin (
                    Priority.HIGH,
                    null,
                    null,
                    (obj, res) => {
                        try {
                            loader.load_async.end (res);
                        } catch (Error e) {
                            var dialog = new Gtk.MessageDialog (
                                this,
                                Gtk.DialogFlags.MODAL
                                | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                Gtk.MessageType.WARNING,
                                Gtk.ButtonsType.CLOSE,
                                _("Can't load from file: %s"),
                                e.message
                            );
                            dialog.response.connect (dialog.destroy);
                            dialog.show ();
                        }
                    }
                );
            });
            file_chooser.show ();
        }

        void action_jump_to_args () {
            if (arguments_revealer.reveal_child)
                ((Gtk.Widget) arguments_box.observe_children ().get_item (0)).grab_focus ();
        }
    }
}
