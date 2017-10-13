/*
 * Copyright 2014-2017 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

namespace Nuvola
{

namespace ConfigKey
{
	public const string WINDOW_X = "nuvola.window.x";
	public const string WINDOW_Y = "nuvola.window.y";
	public const string WINDOW_WIDTH = "nuvola.window.width";
	public const string WINDOW_HEIGHT = "nuvola.window.height";
	public const string WINDOW_MAXIMIZED = "nuvola.window.maximized";
	public const string WINDOW_SIDEBAR_POS = "nuvola.window.sidebar.position";
	public const string WINDOW_SIDEBAR_VISIBLE = "nuvola.window.sidebar.visible";
	public const string WINDOW_SIDEBAR_PAGE = "nuvola.window.sidebar.page";
	public const string DARK_THEME = "nuvola.dark_theme";
}

namespace Actions
{
	public const string ABOUT = "about";
	public const string HELP = "help";
	public const string DONATE = "donate";
	public const string ACTIVATE = "activate";
	public const string GO_HOME = "go-home";
	public const string GO_BACK = "go-back";
	public const string GO_FORWARD = "go-forward";
	public const string GO_RELOAD = "go-reload";
	public const string GO_LOAD_URL = "go-load-url";
	public const string PREFERENCES = "preferences";
	public const string TOGGLE_SIDEBAR = "toggle-sidebar";
	public const string ZOOM_IN = "zoom-in";
	public const string ZOOM_OUT = "zoom-out";
	public const string ZOOM_RESET = "zoom-reset";
}


public string build_ui_runner_ipc_id(string web_app_id)
{
	return "N3" + web_app_id.replace("_", "");
}

public class AppRunnerController: Drtgtk.Application
{
	public Drt.Storage storage {get; private set;}
	public Config config {get; protected set; default = null;}
	public Connection connection {get; protected set;}
	public WebAppWindow? main_window {get; protected set; default = null;}
	public WebApp web_app {get; protected set;}
	public WebAppStorage app_storage {get; protected set;}
	public string dbus_id {get; private set;}
	private WebkitOptions webkit_options;
	private WebkitEngine webkit_engine = null;
	public WebEngine web_engine {get; private set;}
	public Drt.KeyValueStorage master_config {get; private set;}
	public Bindings bindings {get; private set;}
	public IpcBus ipc_bus {get; private set; default=null;}
	public ActionsHelper actions_helper {get; private set; default = null;}
	private AppDbusApi? dbus_api = null;
	private uint dbus_api_id = 0;
	private GlobalKeybindings global_keybindings;
	private const int MINIMAL_REMEMBERED_WINDOW_SIZE = 300;
	private uint configure_event_cb_id = 0;
	private MenuBar menu_bar;
	private Drtgtk.Form? init_form = null;
	private FormatSupport format_support = null;
	private Drt.Lst<Component> components = null;
	private string? api_token = null;
	private bool use_nuvola_dbus = false;
	private HashTable<string, Variant>? web_worker_data = null;
	private StartupWindow? startup_window = null;
	private TiliadoActivation? tiliado_activation = null;
	private URLBar? url_bar = null;
	
	public AppRunnerController(
		Drt.Storage storage, WebApp web_app, WebAppStorage app_storage,
		string? api_token, bool use_nuvola_dbus=false)
	{
		var uid = web_app.get_uid();
		var dbus_id = web_app.get_dbus_id();
		base(uid, web_app.name, dbus_id);
		this.web_app = web_app;
		this.storage = storage;
		this.dbus_id = dbus_id;
		this.icon = web_app.get_icon_name();
		this.version = "%d.%d".printf(web_app.version_major, web_app.version_minor);
		this.app_storage = app_storage;
		this.api_token = api_token;
		this.use_nuvola_dbus = use_nuvola_dbus;
	}
	
	public override bool dbus_register(DBusConnection conn, string object_path)
		throws GLib.Error
	{
		if (!base.dbus_register(conn, object_path))
			return false;
		dbus_api = new AppDbusApi(this);
		dbus_api_id = conn.register_object(object_path, dbus_api);
		return true;
	}
	
	public override void dbus_unregister(DBusConnection conn, string object_path)
	{
		if (dbus_api_id > 0)
		{
			conn.unregister_object(dbus_api_id);
			dbus_api_id = 0;
		}
		base.dbus_unregister(conn, object_path);
	}
	
	public override void apply_custom_styles(Gdk.Screen screen)
	{
		base.apply_custom_styles(screen);
		Nuvola.Css.apply_custom_styles(screen);
	}
	
	private  void start()
	{
		init_settings();
		format_support = new FormatSupport(storage.require_data_file("audio/audiotest.mp3").get_path());
		webkit_options = new WebkitOptions(app_storage);
		var startup_check = new StartupCheck(web_app, format_support, webkit_options);
		startup_window = new StartupWindow(this, startup_check);
		startup_window.present();
		startup_check.check_desktop_portal_available.begin((o, res) => startup_check.check_desktop_portal_available.end(res));
		startup_check.check_app_requirements.begin((o, res) => startup_check.check_app_requirements.end(res));
		startup_check.check_graphics_drivers.begin((o, res) => startup_check.check_graphics_drivers.end(res));
		startup_check.task_finished.connect_after(on_startup_check_task_finished);
	}
	
	private void on_startup_check_task_finished(GLib.Object emitter, string task_name)
	{
		var startup_check = emitter as StartupCheck;
		assert(startup_check != null);
		if (startup_check.finished_tasks == 3 && startup_check.running_tasks == 0)
		{
			if (startup_check.get_overall_status() == StartupCheck.Status.ERROR)
			{
				startup_check.task_finished.disconnect(on_startup_check_task_finished);
				startup_window.ready_to_continue.connect(on_startup_window_ready_to_continue);
				startup_check.mark_as_finished();
			}
			else
			{
				startup_check.task_finished.disconnect(on_startup_check_task_finished);
				startup_window.ready_to_continue.connect(on_startup_window_ready_to_continue);
				#if !TILIADO_API
				init_ipc(startup_check);
				startup_check.mark_as_finished();
				#else
				if (init_ipc(startup_check))
				{
					tiliado_activation = new TiliadoActivationClient(ipc_bus.master);
					startup_check.check_tiliado_account.begin(
						tiliado_activation, () => startup_check.mark_as_finished());
				}
				#endif
			}
		}
	}
	
	private void on_startup_window_ready_to_continue(StartupWindow window)
	{
		var status = startup_window.model.final_status;
		startup_window.ready_to_continue.disconnect(on_startup_window_ready_to_continue);
		startup_window.destroy();
		startup_window = null;
		switch (status)
		{
		case StartupCheck.Status.WARNING:
		case StartupCheck.Status.OK:
			init_gui();
			init_web_engine();
			break;
		}
	}
	
	private void init_settings()
	{
		/* Disable GStreamer plugin helper because it is shown too often and quite annoying.  */
		Environment.set_variable("GST_INSTALL_PLUGINS_HELPER", "/bin/true", true);
		web_worker_data = new HashTable<string, Variant>(str_hash, str_equal);
		
		var gtk_settings = Gtk.Settings.get_default();
		var default_config = new HashTable<string, Variant>(str_hash, str_equal);
		default_config.insert(ConfigKey.WINDOW_X, new Variant.int64(-1));
		default_config.insert(ConfigKey.WINDOW_Y, new Variant.int64(-1));
		default_config.insert(ConfigKey.WINDOW_SIDEBAR_POS, new Variant.int64(-1));
		default_config.insert(ConfigKey.WINDOW_SIDEBAR_VISIBLE, new Variant.boolean(false));
		default_config.insert(
			ConfigKey.DARK_THEME, new Variant.boolean(gtk_settings.gtk_application_prefer_dark_theme));
		config = new Config(app_storage.config_dir.get_child("config.json"), default_config);
		config.changed.connect(on_config_changed);
		gtk_settings.gtk_application_prefer_dark_theme = config.get_bool(ConfigKey.DARK_THEME);
	}
	
	private bool init_ipc(StartupCheck startup_check)
	{	
		try
		{
			var bus_name = build_ui_runner_ipc_id(web_app.id);
			web_worker_data["WEB_APP_ID"] = web_app.id;
			web_worker_data["RUNNER_BUS_NAME"] = bus_name;
			ipc_bus = new IpcBus(bus_name);
			ipc_bus.start();
			if (use_nuvola_dbus)
			{
				var nuvola_api = Bus.get_proxy_sync<DbusIfce>(
					BusType.SESSION, Nuvola.get_dbus_id(), Nuvola.get_dbus_path(),
					DBusProxyFlags.DO_NOT_CONNECT_SIGNALS|DBusProxyFlags.DO_NOT_LOAD_PROPERTIES);
				GLib.Socket socket;
				nuvola_api.get_connection(this.web_app.id, this.dbus_id, out socket, out api_token);
				if (socket == null)
				{
					startup_check.nuvola_service_message = (
						"<b>Nuvola Apps Runtime Service refused connection.</b>\n\n"
						+ "1. Make sure Nuvola Apps Runtime is installed.\n"
						+ "2. Launch Nuvola Apps Runtime to find out whether activation"
						+ " (Premium/Patron account) is required.\n"
						+ "3. If Nuvola has been updated recently, close all Nuvola Apps and try launching it again.");
					startup_check.nuvola_service_status = StartupCheck.Status.ERROR;
					return false;
				}
				ipc_bus.connect_master_socket(socket, api_token);
			}
			else
			{
				bus_name = Environment.get_variable("NUVOLA_IPC_MASTER");
				assert(bus_name != null);
				ipc_bus.connect_master(bus_name, api_token);
			}
		}
		catch (GLib.Error e)
		{
			startup_check.nuvola_service_message = Markup.printf_escaped(
				"<b>Failed to connect to Nuvola Apps Runtime Service.</b>\n\n"
				+ "1. Make sure Nuvola Apps Runtime is installed.\n"
				+ "2. Launch Nuvola Apps Runtime to find out whether activation"
				+ " (Premium/Patron account) is required.\n"
				+ "3. If Nuvola has been updated recently, close all Nuvola Apps and try launching it again.\n\n"
				+ "<i>Error message: %s</i>", e.message);
			startup_check.nuvola_service_status = StartupCheck.Status.ERROR;
			
			return false;
		}
		
		ipc_bus.router.add_method(IpcApi.CORE_GET_METADATA, Drt.RpcFlags.READABLE|Drt.RpcFlags.PRIVATE,
			"Get web app metadata.", handle_get_metadata, null);
		
		try
		{
			var response = ipc_bus.master.call_sync("/nuvola/core/runner-started", new Variant("(ss)", web_app.id, ipc_bus.router.hex_token));
			assert(response.equal(new Variant.boolean(true)));
		}
		catch (GLib.Error e)
		{
			startup_check.nuvola_service_message = Markup.printf_escaped(
				"<b>Communication with Nuvola Apps Runtime Service failed.</b>\n\n"
				+ "1. Make sure Nuvola Apps Runtime is installed.\n"
				+ "2. Launch Nuvola Apps Runtime to find out whether activation"
				+ " (Premium/Patron account) is required.\n"
				+ "3. If Nuvola has been updated recently, close all Nuvola Apps and try launching it again.\n\n"
				+ "<i>Error message: %s</i>", e.message);
			startup_check.nuvola_service_status = StartupCheck.Status.ERROR;
		}
		
		var storage_client = new Drt.KeyValueStorageClient(ipc_bus.master);
		master_config = storage_client.get_proxy("master.config");
		ipc_bus.router.add_method("/nuvola/core/get-component-info", Drt.RpcFlags.READABLE,
			"Get info about component.",
			handle_get_component_info, {
			new Drt.StringParam("name", true, false, null, "Component name.")
			});
		ipc_bus.router.add_method("/nuvola/core/toggle-component-active", Drt.RpcFlags.WRITABLE|Drt.RpcFlags.PRIVATE,
			"Set whether the component is active.",
			handle_toggle_component_active, {
			new Drt.StringParam("name", true, false, null, "Component name."),
			new Drt.BoolParam("name", true, false, "Component active state.")
			});
		startup_check.nuvola_service_status = StartupCheck.Status.OK;
		return true;
	}
	
	private void init_gui()
	{
		actions_helper = new ActionsHelper(actions, config);
		unowned ActionsHelper ah = actions_helper;
		Drtgtk.Action[] actions_spec = {
		//          Action(group, scope, name, label?, mnemo_label?, icon?, keybinding?, callback?)
		ah.simple_action("main", "app", Actions.ACTIVATE, "Activate main window", null, null, null, do_activate),
		ah.simple_action("main", "app", Actions.QUIT, "Quit", "_Quit", "application-exit", "<ctrl>Q", do_quit),
		ah.simple_action("main", "app", Actions.ABOUT, "About", "_About", null, null, do_about),
		ah.simple_action("main", "app", Actions.HELP, "Help", "_Help", null, "F1", do_help),
		};
		actions.add_actions(actions_spec);
				
		menu_bar = new MenuBar(this);
		menu_bar.update();
		set_app_menu_items({Actions.HELP, Actions.ABOUT, Actions.QUIT});
		
		main_window = new WebAppWindow(this);
		main_window.can_destroy.connect(on_can_quit);
		var x = (int) config.get_int64(ConfigKey.WINDOW_X);
		var y = (int) config.get_int64(ConfigKey.WINDOW_Y);
		if (x >= 0 && y >= 0)
			main_window.move(x, y);
		var win_width = (int) config.get_int64(ConfigKey.WINDOW_WIDTH);
		var win_height = (int) config.get_int64(ConfigKey.WINDOW_HEIGHT);
		if (win_width > MINIMAL_REMEMBERED_WINDOW_SIZE && win_height > MINIMAL_REMEMBERED_WINDOW_SIZE)
			main_window.resize(win_width, win_height);
		if (config.get_bool(ConfigKey.WINDOW_MAXIMIZED))
			main_window.maximize();
		
		if (tiliado_activation != null) {
			var trial_widget = new TiliadoTrialWidget(this.tiliado_activation, this, TiliadoMembership.BASIC);
			main_window.top_grid.add(trial_widget);
		}
		main_window.present();
		main_window.window_state_event.connect(on_window_state_event);
		main_window.configure_event.connect(on_configure_event);
		main_window.notify["is-active"].connect_after(on_window_is_active_changed);
		main_window.sidebar.hide();
		
		fatal_error.connect(on_fatal_error);
		show_error.connect(on_show_error);
		show_warning.connect(on_show_warning);
	}
	
	private void init_web_engine()
	{
		connection = new Connection(new Soup.Session(), app_storage.cache_dir.get_child("conn"), config);
		if (!WebOptions.set_default(typeof(WebkitOptions))) {
			warning("Default engine is %s.", WebOptions.get_default().name());
		}
		var web_options = WebOptions.create_default(app_storage);
		web_engine = web_options.create_web_engine();
		webkit_engine = web_engine as WebkitEngine;
		if (webkit_engine == null) {
			webkit_engine = new WebkitEngine(webkit_options);
		}
		web_engine.early_init(this, ipc_bus, web_app, config, connection, web_worker_data);
		web_engine.set_user_agent(web_app.user_agent);
		web_engine.set_web_plugins(web_app.traits(webkit_options).flash_required);
		web_engine.set_media_source_extension(web_app.traits(webkit_options).mse_required);
		
		web_engine.init_form.connect(on_init_form);
		web_engine.notify.connect_after(on_web_engine_notify);
		web_engine.show_alert_dialog.connect(on_show_alert_dialog);
		actions.action_changed.connect(on_action_changed);
		var widget = web_engine.get_main_web_view();
		widget.hexpand = widget.vexpand = true;
		main_window.grid.add(widget);
		widget.show();
		web_engine.init_finished.connect(init_app_runner);
		web_engine.app_runner_ready.connect(load_app);
		
		/* It is necessary to init WebEngine after format support check because WebKitPluginProcess2
		 * must not be terminated during plugin discovery process. Issue: tiliado/nuvolaruntime#354 */
		web_engine.init();
	}
	
	private void init_app_runner()
	{
		append_actions();
		var gakb = new ActionsKeyBinderClient(ipc_bus.master);
		global_keybindings = new GlobalKeybindings(gakb, actions);
		load_extensions();
		web_engine.get_main_web_view().hide();
		main_window.sidebar.hide();
		web_engine.init_app_runner();
	}
	
	private void load_app()
	{
		set_app_menu_items({Actions.PREFERENCES, Actions.HELP, Actions.ABOUT, Actions.QUIT});
		main_window.set_menu_button_items({
			Actions.ZOOM_IN, Actions.ZOOM_OUT, Actions.ZOOM_RESET, "|",
			Actions.TOGGLE_SIDEBAR, "|", Actions.GO_LOAD_URL});
		main_window.create_toolbar({Actions.GO_BACK, Actions.GO_FORWARD, Actions.GO_RELOAD, Actions.GO_HOME});
		
		main_window.sidebar.add_page.connect_after(on_sidebar_page_added);
		main_window.sidebar.remove_page.connect_after(on_sidebar_page_removed);
		
		if (config.get_bool(ConfigKey.WINDOW_SIDEBAR_VISIBLE))
			main_window.sidebar.show();
		else
			main_window.sidebar.hide();
		main_window.sidebar_position = (int) config.get_int64(ConfigKey.WINDOW_SIDEBAR_POS);
		var sidebar_page = config.get_string(ConfigKey.WINDOW_SIDEBAR_PAGE);
		if (sidebar_page != null)
			main_window.sidebar.page = sidebar_page;
		main_window.notify["sidebar-position"].connect_after((o, p) =>
		{
			config.set_int64(ConfigKey.WINDOW_SIDEBAR_POS, (int64) main_window.sidebar_position);
		});
		main_window.sidebar.notify["visible"].connect_after(on_sidebar_visibility_changed);
		main_window.sidebar.page_changed.connect(on_sidebar_page_changed);
		web_engine.get_main_web_view().show();
	
		menu_bar.set_menu("01_go", "_Go", {Actions.GO_HOME, Actions.GO_RELOAD, Actions.GO_BACK, Actions.GO_FORWARD});
		menu_bar.set_menu("02_view", "_View", {Actions.ZOOM_IN, Actions.ZOOM_OUT, Actions.ZOOM_RESET, "|", Actions.TOGGLE_SIDEBAR});
		web_engine.load_app();
	}
	
	public override void activate()
	{
		if (main_window != null)
			main_window.present();
		else if (startup_window != null)
			startup_window.present();
		else
			start();
	}
	
	private void append_actions()
	{
		unowned ActionsHelper ah = actions_helper;
		Drtgtk.Action[] actions_spec = {
		ah.simple_action("main", "app", Actions.PREFERENCES, "Preferences", "_Preferences", null, null, do_preferences),
		ah.toggle_action("main", "win", Actions.TOGGLE_SIDEBAR, "Show sidebar", "Show _sidebar", null, null, do_toggle_sidebar, config.get_value(ConfigKey.WINDOW_SIDEBAR_VISIBLE)),
		ah.simple_action("go", "app", Actions.GO_HOME, "Home", "_Home", "go-home", "<alt>Home", web_engine.go_home),
		ah.simple_action("go", "app", Actions.GO_BACK, "Back", "_Back", "go-previous", "<alt>Left", web_engine.go_back),
		ah.simple_action("go", "app", Actions.GO_FORWARD, "Forward", "_Forward", "go-next", "<alt>Right", web_engine.go_forward),
		ah.simple_action("go", "app", Actions.GO_RELOAD, "Reload", "_Reload", "view-refresh", "<ctrl>R", web_engine.reload),
		ah.simple_action("go", "app", Actions.GO_LOAD_URL, "Load URL...", null, null, "<ctrl>L", do_load_url),
		ah.simple_action("view", "win", Actions.ZOOM_IN, "Zoom in", null, "zoom-in", "<ctrl>plus", web_engine.zoom_in),
		ah.simple_action("view", "win", Actions.ZOOM_OUT, "Zoom out", null, "zoom-out", "<ctrl>minus", web_engine.zoom_out),
		ah.simple_action("view", "win", Actions.ZOOM_RESET, "Original zoom", null, "zoom-original", "<ctrl>0", web_engine.zoom_reset),
		};
		actions.add_actions(actions_spec);
		actions.get_action(Actions.GO_FORWARD).enabled = web_engine.can_go_forward;
		actions.get_action(Actions.GO_BACK).enabled = web_engine.can_go_back;
	}
	
	private void do_quit()
	{
		var windows = Gtk.Window.list_toplevels();
		foreach (var window in windows)
			window.hide();
		Timeout.add_seconds(10, () => {warning("Force quit after timeout."); GLib.Process.exit(0);});
		quit();
	}
	
	private void do_activate()
	{
		activate();
	}
	
	private void do_about()
	{
		var dialog = new AboutDialog(main_window, web_app);
		dialog.run();
		dialog.destroy();
	}
	
	private void do_preferences()
	{
		var values = new HashTable<string, Variant>(str_hash, str_equal);
		values.insert(ConfigKey.DARK_THEME, config.get_value(ConfigKey.DARK_THEME));
		Drtgtk.Form form;
		try
		{
			form = Drtgtk.Form.create_from_spec(values, new Variant.tuple({
				new Variant.tuple({new Variant.string("header"), new Variant.string("Basic settings")}),
				new Variant.tuple({new Variant.string("bool"), new Variant.string(ConfigKey.DARK_THEME), new Variant.string("Prefer dark theme")})
			}));
		}
		catch (Drtgtk.FormError e)
		{
			show_error("Preferences form error",
				"Preferences form hasn't been shown because of malformed form specification: %s"
				.printf(e.message));
			return;
		}
		
		try
		{
			Variant? extra_values = null;
			Variant? extra_entries = null;
			web_engine.get_preferences(out extra_values, out extra_entries);
			form.add_values(Drt.variant_to_hashtable(extra_values));
			form.add_entries(extra_entries);
		}
		catch (Drtgtk.FormError e)
		{
			show_error("Preferences form error",
				"Some entries of the Preferences form haven't been shown because of malformed form specification: %s"
				.printf(e.message));
		}
		
		var dialog = new PreferencesDialog(this, main_window, form);
		dialog.add_tab("Keyboard shortcuts", new KeybindingsSettings(actions, config, global_keybindings.keybinder));
		var network_settings = new NetworkSettings(connection);
		dialog.add_tab("Network", network_settings);
		dialog.add_tab("Features", new ComponentsManager(this, components, tiliado_activation));
		if (webkit_engine != null) {
			dialog.add_tab("Website Data", new WebsiteDataManager(webkit_options.default_context.get_website_data_manager()));
			dialog.add_tab("Format Support", new FormatSupportScreen(this, format_support, storage, webkit_options.default_context));
		}
		
		var response = dialog.run();
		if (response == Gtk.ResponseType.OK)
		{
			var new_values = form.get_values();
			foreach (var key in new_values.get_keys())
			{
				var new_value = new_values.get(key);
				if (new_value == null)
					critical("New value '%s' not found", key);
				else
					config.set_value(key, new_value);
			}
			NetworkProxyType type;
			string? host;
			int port;
			if (network_settings.get_proxy_settings(out type, out host, out port))
			{
				debug("New network proxy settings: %s %s %d", type.to_string(), host, port);
				connection.set_network_proxy(type, host, port);
				web_engine.apply_network_proxy(connection);
			}
		}
		// Don't destroy dialog before form data are retrieved
		dialog.destroy();
	}
	
	private void do_toggle_sidebar()
	{
		var sidebar = main_window.sidebar;
		if (sidebar.visible)
			sidebar.hide();
		else
			sidebar.show();
	}
	
	private void do_help()
	{
		show_uri(Nuvola.HELP_URL);
	}
	
	private void do_load_url() {
		var url = web_engine.get_url();
		if (url_bar == null) {
			url_bar = new URLBar((owned) url);
		} else {
			url_bar.url = (owned) url;
		}
		var header_bar = main_window.header_bar;
		if (header_bar.custom_title != url_bar) {
			url_bar.show();
			header_bar.custom_title = url_bar;
			url_bar.response.connect(on_url_bar_response);
		}
		url_bar.entry.grab_focus();
	}
	
	private void on_url_bar_response(URLBar bar, bool response) {
		main_window.header_bar.custom_title = null;
		url_bar = null;
		bar.response.disconnect(on_url_bar_response);
		if (response) {
			var url = bar.url;
			if (!Drt.String.is_empty(url)) {
				web_engine.load_url(url);
			}
		}
	}
	
	private void load_extensions()
	{	
		var router = ipc_bus.router;
		var web_worker = web_engine.web_worker;
		bindings = new Bindings();
		bindings.add_binding(new ActionsBinding(router, web_worker));
		bindings.add_binding(new NotificationsBinding(router, web_worker));
		bindings.add_binding(new NotificationBinding(router, web_worker));
		bindings.add_binding(new LauncherBinding(router, web_worker));
		bindings.add_binding(new MediaKeysBinding(router, web_worker));
		bindings.add_binding(new MenuBarBinding(router, web_worker));
		bindings.add_binding(new MediaPlayerBinding(router, web_worker, new MediaPlayer(actions)));
		bindings.add_object(actions_helper);
		
		components = new Drt.Lst<Component>();
		components.prepend(new TrayIconComponent(this, bindings, config));
		components.prepend(new UnityLauncherComponent(this, bindings, config));
		components.prepend(new NotificationsComponent(this, bindings, actions_helper));
		components.prepend(new MediaKeysComponent(this, bindings, config, ipc_bus.master, web_app.id));
		
		bindings.add_object(menu_bar);
		
		components.prepend(new PasswordManagerComponent(config, ipc_bus, web_worker, web_app.id, webkit_engine));
		components.prepend(new AudioScrobblerComponent(this, bindings, master_config, config, connection.session));
		components.prepend(new MPRISComponent(this, bindings, config));
		components.prepend(new HttpRemoteControl.Component(this, bindings, config, ipc_bus));
		components.prepend(new LyricsComponent(this, bindings, config));
		components.prepend(new DeveloperComponent(this, bindings, config));
		components.reverse();
		
		foreach (var component in components)
		{
			if (!component.is_membership_ok(tiliado_activation))
				component.toggle(false);
			if (component.available && component.enabled)
				component.auto_load();
			debug("Component %s (%s) %s", component.id, component.name,
				component.available && component.enabled ? "enabled": "not enabled");
			component.notify["enabled"].connect_after(on_component_enabled_changed);
		}
	}
	
	private void on_fatal_error(string title, string message, bool markup) {
		var dialog = new Drtgtk.ErrorDialog(
			title,
			message + "\n\nThe application has reached an inconsistent state and will quit for that reason.",
			markup);
		dialog.run();
		dialog.destroy();
	}
	
	private void on_show_error(string title, string message, bool markup) {
		var dialog = new Drtgtk.ErrorDialog(
			title,
			message + "\n\nThe application might not function properly.",
			markup);
		Idle.add(() => {
			dialog.run();
			dialog.destroy();
			return false;
		});
	}
	
	private void on_show_warning(string title, string message)
	{
		var info_bar = new Gtk.InfoBar();
		info_bar.show_close_button = true;
		var label = new Gtk.Label(Markup.printf_escaped("<span size='medium'><b>%s</b></span> %s", title, message));
		label.use_markup = true;
		label.vexpand = false;
		label.hexpand = true;
		label.halign = Gtk.Align.START;
		label.set_line_wrap(true);
		(info_bar.get_content_area() as Gtk.Container).add(label);
		info_bar.response.connect(on_close_warning);
		info_bar.show_all();
		main_window.info_bars.add(info_bar);
	}
	
	private void on_close_warning(Gtk.InfoBar info_bar, int response_id)
	{
		(info_bar.get_parent() as Gtk.Container).remove(info_bar);
	}
	
	private bool on_window_state_event(Gdk.EventWindowState event)
	{
		bool m = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
		config.set_bool(ConfigKey.WINDOW_MAXIMIZED, m);
		return false;
	}
	
	private void on_window_is_active_changed(Object o, ParamSpec p)
	{
		if (!main_window.is_active)
			return;
		
		try
		{
			var response = ipc_bus.master.call_sync("/nuvola/core/runner-activated", new Variant("(s)", web_app.id));
			warn_if_fail(response.equal(new Variant.boolean(true)));
		}
		catch (GLib.Error e)
		{
			critical("Communication with master process failed: %s", e.message);
		}
	}
	
	private bool on_configure_event(Gdk.EventConfigure event)
	{
		if (configure_event_cb_id != 0)
			Source.remove(configure_event_cb_id);
		configure_event_cb_id = Timeout.add(200, on_configure_event_cb);
		return false;
	}
	
	private bool on_configure_event_cb()
	{
		configure_event_cb_id = 0;
		if (!main_window.maximized)
		{
			int x;
			int y;
			int width;
			int height;
			main_window.get_position (out x, out y);
			main_window.get_size(out width, out height);
			config.set_int64(ConfigKey.WINDOW_X, (int64) x);
			config.set_int64(ConfigKey.WINDOW_Y, (int64) y);
			config.set_int64(ConfigKey.WINDOW_WIDTH, (int64) width);
			config.set_int64(ConfigKey.WINDOW_HEIGHT, (int64) height);
		}
		return false;
	}
	
	private void on_component_enabled_changed(GLib.Object object, ParamSpec param)
	{
		var component = object as Component;
		return_if_fail(component != null);
		var signal_name = component.enabled ? "ComponentLoaded" : "ComponentUnloaded";
		var payload = new Variant("(sss)", signal_name, component.id, component.name);
		try
		{
			
			web_engine.call_function_sync("Nuvola.core.emit", ref payload);
		}
		catch (GLib.Error e)
		{
			warning("Communication with web engine failed: %s", e.message);
		}
		try
		{
			web_engine.web_worker.call_function_sync("Nuvola.core.emit", ref payload);
		}
		catch (GLib.Error e)
		{
			warning("Communication with web worker failed: %s", e.message);
		}
	}
	
	private void handle_get_metadata(Drt.RpcRequest request) throws Drt.RpcError
	{
		request.respond(web_app.to_variant());
	}
	
	private void handle_get_component_info(Drt.RpcRequest request) throws Drt.RpcError
	{
		var id = request.pop_string();
		if (components != null)
		{
			foreach (var component in components)
			{
				if (id == component.id)
				{
					var builder = new VariantBuilder(new VariantType("a{smv}"));
					builder.add("{smv}", "name", new Variant.string(component.name));
					builder.add("{smv}", "found", new Variant.boolean(true));
					builder.add("{smv}", "loaded", new Variant.boolean(component.enabled));
					builder.add("{smv}", "active", new Variant.boolean(component.active));
					request.respond(builder.end());
					return;
				}
			}
		}
		var builder = new VariantBuilder(new VariantType("a{smv}"));
		builder.add("{smv}", "name", new Variant.string(""));
		builder.add("{smv}", "found", new Variant.boolean(false));
		builder.add("{smv}", "loaded", new Variant.boolean(false));
		request.respond(builder.end());
	}
	
	private void handle_toggle_component_active(Drt.RpcRequest request) throws Drt.RpcError
	{
		var id = request.pop_string();
		var active = request.pop_bool();
		if (components != null)
		{
			foreach (var component in components)
			{
				if (id == component.id) {
					request.respond(new Variant.boolean(component.toggle_active(active)));
					return;
				}
			}
		}
		request.respond(new Variant.boolean(false));
	}
	
	private void on_action_changed(Drtgtk.Action action, ParamSpec p)
	{
		if (p.name != "enabled")
			return;
		try
		{
			var payload = new Variant("(ssb)", "ActionEnabledChanged", action.name, action.enabled);
			web_engine.web_worker.call_function_sync("Nuvola.actions.emit", ref payload);
		}
		catch (GLib.Error e)
		{
			if (e is Drt.RpcError.NOT_READY)
				debug("Communication failed: %s", e.message);
			else
				warning("Communication failed: %s", e.message);
		}
	}
	
	private void on_config_changed(string key, Variant? old_value)
	{
		switch (key)
		{
		case ConfigKey.DARK_THEME:
			Gtk.Settings.get_default().gtk_application_prefer_dark_theme = config.get_bool(ConfigKey.DARK_THEME);
			break;
		}
		
		if (web_engine.web_worker.ready)
		{
			try
			{
				var payload = new Variant("(ss)", "ConfigChanged", key);
				web_engine.web_worker.call_function("Nuvola.config.emit", ref payload);
			}
			catch (GLib.Error e)
			{
				warning("Communication failed: %s", e.message);
			}
		}
	}
	
	private void on_web_engine_notify(GLib.Object o, ParamSpec p) {
		switch (p.name) {
		case "can-go-forward":
			actions.get_action(Actions.GO_FORWARD).enabled = web_engine.can_go_forward;
			break;
		case "can-go-back":
			actions.get_action(Actions.GO_BACK).enabled = web_engine.can_go_back;
			break;
		case "is-loading":
			var title_bar = main_window.headerbar_title;
			if (web_engine.is_loading) {
				var spinner = new Gtk.Spinner();
				spinner.start();
				spinner.show();
				title_bar.set_start_widget(spinner);
				title_bar.set_subtitle("loading...");
			} else {
				title_bar.set_start_widget(null);
				title_bar.set_subtitle(null);
			}
			break;
		}
	}
	
	private void on_can_quit(ref bool can_quit)
	{
		if (web_engine != null)
		{
			try
			{
				if (web_engine.web_worker.ready)
					can_quit = web_engine.web_worker.send_data_request_bool("QuitRequest", "approved", can_quit);
				else
					debug("WebWorker not ready");
			}
			catch (GLib.Error e)
			{
				warning("QuitRequest failed in web worker: %s", e.message);
			}
			try
			{
			
				if (web_engine.ready)
					can_quit = web_engine.send_data_request_bool("QuitRequest", "approved", can_quit);
				else
					debug("WebEngine not ready");
			}
			catch (GLib.Error e)
			{
				warning("QuitRequest failed in web engine: %s", e.message);
			}
		}
	}
	
	private void on_init_form(HashTable<string, Variant> values, Variant entries)
	{
		if (init_form != null)
		{
			main_window.overlay.remove(init_form);
			init_form = null;
		}
		
		try
		{
			init_form = Drtgtk.Form.create_from_spec(values, entries);
			init_form.check_toggles();
			init_form.expand = true;
			init_form.valign = init_form.halign = Gtk.Align.CENTER;
			init_form.show();
			var button = new Gtk.Button.with_label("OK");
			button.margin = 10;
			button.show();
			button.clicked.connect(on_init_form_button_clicked);
			init_form.attach_next_to(button, null, Gtk.PositionType.BOTTOM, 2, 1);
			main_window.grid.add(init_form);
			init_form.show();
		}
		catch (Drtgtk.FormError e)
		{
			show_error("Initialization form error",
				"Initialization form hasn't been shown because of malformed form specification: %s"
				.printf(e.message));
		}
	}
	
	private void on_init_form_button_clicked(Gtk.Button button)
	{
		button.clicked.disconnect(on_init_form_button_clicked);
		main_window.grid.remove(init_form);
		var new_values = init_form.get_values();
		init_form = null;
		
		foreach (var key in new_values.get_keys())
		{
			var new_value = new_values.get(key);
			if (new_value == null)
				critical("New values '%s'' not found", key);
			else
				config.set_value(key, new_value);
		}
		
		web_engine.init_app_runner();
	}
	
	private void on_sidebar_visibility_changed(GLib.Object o, ParamSpec p)
	{
		var visible = main_window.sidebar.visible;
		config.set_bool(ConfigKey.WINDOW_SIDEBAR_VISIBLE, visible);
		if (visible)
			main_window.sidebar_position = (int) config.get_int64(ConfigKey.WINDOW_SIDEBAR_POS);
		
		actions.get_action(Actions.TOGGLE_SIDEBAR).state = new Variant.boolean(visible);
	}
	
	private void on_sidebar_page_changed()
	{
		var page = main_window.sidebar.page;
		if (page != null)
			config.set_string(ConfigKey.WINDOW_SIDEBAR_PAGE, page);
	}
	
	private void on_sidebar_page_added(Sidebar sidebar, string name, string label, Gtk.Widget child)
	{
		actions.get_action(Actions.TOGGLE_SIDEBAR).enabled = !sidebar.is_empty();
	}
	
	private void on_sidebar_page_removed(Sidebar sidebar, Gtk.Widget child)
	{
		actions.get_action(Actions.TOGGLE_SIDEBAR).enabled = !sidebar.is_empty();
	}
	
	private void on_show_alert_dialog(ref bool handled, string text)
	{
		main_window.show_overlay_alert(text);
		handled = true;
	}
}


[DBus(name="eu.tiliado.NuvolaApp")]
public class AppDbusApi: GLib.Object
{
	private unowned AppRunnerController controller;
	
	public AppDbusApi(AppRunnerController controller)
	{
		this.controller = controller;
	}
	
	public void activate()
	{
		Idle.add(() => {controller.activate(); return false;});
	}
}


[DBus(name="eu.tiliado.Nuvola")]
public interface DbusIfce: GLib.Object
{
	public abstract void get_connection(string app_id, string dbus_id, out GLib.Socket? socket, out string? token) throws GLib.Error;
}

} // namespace Nuvola
