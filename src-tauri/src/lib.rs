use std::io::{BufRead, BufReader};
use std::net::{SocketAddr, TcpStream};
#[cfg(unix)]
use std::os::unix::process::CommandExt;
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use std::process::{Command as StdCommand, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::json;
use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};
use tauri::{Emitter, Manager, RunEvent, Window};

#[cfg(windows)]
const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;

#[cfg(unix)]
fn kill_backend(pid: i32) {
    unsafe {
        libc::kill(-pid, libc::SIGKILL);
    }
}

#[cfg(windows)]
fn kill_backend(pid: i32) {
    let _ = StdCommand::new("taskkill")
        .args(["/PID", &pid.to_string(), "/T", "/F"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

// The Elixir (Burrito) backend serves the LiveView on this port.
const BACKEND_URL: &str = "http://localhost:14041";
const BACKEND_ADDR: &str = "127.0.0.1:14041";

#[tauri::command]
fn set_window_size(window: Window, width: f64, height: f64) {
    let _ = window.set_size(tauri::LogicalSize::new(width, height));
}

fn build_menu(app: &tauri::App) -> tauri::Result<()> {
    let handle = app.handle();

    let dashboard = MenuItemBuilder::with_id("dashboard", "Dashboard")
        .accelerator("CmdOrCtrl+D")
        .build(handle)?;
    let prefs = MenuItemBuilder::with_id("prefs", "Preferences")
        .accelerator("CmdOrCtrl+,")
        .build(handle)?;
    let oases = MenuItemBuilder::with_id("oases", "Oases")
        .accelerator("CmdOrCtrl+O")
        .build(handle)?;
    let unshown = MenuItemBuilder::with_id("unshown", "Unshown")
        .accelerator("CmdOrCtrl+U")
        .build(handle)?;
    let profile = MenuItemBuilder::with_id("profile", "My Profile")
        .accelerator("CmdOrCtrl+Shift+P")
        .build(handle)?;
    let reload = MenuItemBuilder::with_id("reload", "Reload")
        .accelerator("CmdOrCtrl+R")
        .build(handle)?;
    let close_window = PredefinedMenuItem::close_window(handle, None)?;
    let about = PredefinedMenuItem::about(handle, Some("About Catenary"), None)?;
    let quit = PredefinedMenuItem::quit(handle, Some("Quit Catenary"))?;

    let catenary = SubmenuBuilder::new(handle, "Catenary")
        .item(&about)
        .separator()
        .item(&prefs)
        .separator()
        .item(&quit)
        .build()?;
    let go = SubmenuBuilder::new(handle, "Go")
        .item(&dashboard)
        .separator()
        .item(&oases)
        .item(&unshown)
        .separator()
        .item(&profile)
        .build()?;
    let view = SubmenuBuilder::new(handle, "View").item(&reload).build()?;
    let window = SubmenuBuilder::new(handle, "Window")
        .item(&close_window)
        .build()?;

    let menu = MenuBuilder::new(handle)
        .item(&catenary)
        .item(&go)
        .item(&view)
        .item(&window)
        .build()?;

    app.set_menu(menu)?;
    Ok(())
}

fn start_backend(pid: Arc<Mutex<Option<i32>>>) {
    std::thread::spawn(move || {
        let mut exe = match std::env::current_exe() {
            Ok(exe) => exe,
            Err(err) => {
                eprintln!("[catenary] unable to resolve the app executable: {err}");
                return;
            }
        };
        exe.set_file_name("catenary-backend");

        let mut command = StdCommand::new(exe);
        #[cfg(unix)]
        command
            .arg("--no-halt")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0);
        #[cfg(windows)]
        command
            .arg("--no-halt")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .creation_flags(CREATE_NEW_PROCESS_GROUP);

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(err) => {
                eprintln!("[catenary] failed to spawn the backend: {err}");
                return;
            }
        };

        *pid.lock().unwrap() = Some(child.id() as i32);
        println!("[catenary] backend started");

        let stdout = child.stdout.take().map(BufReader::new);
        let stderr = child.stderr.take().map(BufReader::new);

        let mut threads = Vec::new();
        if let Some(stdout) = stdout {
            threads.push(std::thread::spawn(move || {
                for line in stdout.lines().map_while(Result::ok) {
                    println!("[catenary] {}", line.trim_end());
                }
            }));
        }
        if let Some(stderr) = stderr {
            threads.push(std::thread::spawn(move || {
                for line in stderr.lines().map_while(Result::ok) {
                    eprintln!("[catenary] {}", line.trim_end());
                }
            }));
        }

        let _ = child.wait();
    });
}

fn wait_for_backend() {
    let addr: SocketAddr = BACKEND_ADDR.parse().expect("valid socket address");
    let mut attempts = 0;
    while attempts < 150 {
        if TcpStream::connect_timeout(&addr, Duration::from_millis(200)).is_ok() {
            return;
        }
        std::thread::sleep(Duration::from_millis(200));
        attempts += 1;
    }
    eprintln!("[catenary] backend did not come up in time");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let backend_pid: Arc<Mutex<Option<i32>>> = Arc::new(Mutex::new(None));
    let exit_pid = backend_pid.clone();
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![set_window_size])
        .setup(|app| {
            build_menu(app)?;
            start_backend(backend_pid);

            let handle = app.handle().clone();
            std::thread::spawn(move || {
                wait_for_backend();
                if let Some(window) = handle.get_webview_window("main") {
                    let _ = window.navigate(BACKEND_URL.parse().expect("valid backend URL"));
                }
            });

            Ok(())
        })
        .on_menu_event(|app, event| match event.id().as_ref() {
            "dashboard" => {
                let _ = app.emit_to("main", "catenary-menu", json!({ "view": "dashboard" }));
            }
            "prefs" => {
                let _ = app.emit_to(
                    "main",
                    "catenary-menu",
                    json!({ "view": "prefs", "entry": "none" }),
                );
            }
            "oases" => {
                let _ = app.emit_to(
                    "main",
                    "catenary-menu",
                    json!({ "view": "oases", "entry": "none" }),
                );
            }
            "unshown" => {
                let _ = app.emit_to(
                    "main",
                    "catenary-menu",
                    json!({ "view": "unshown", "entry": "all" }),
                );
            }
            "profile" => {
                let _ = app.emit_to("main", "catenary-menu", json!({ "value": "origin" }));
            }
            "reload" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.reload();
                }
            }
            _ => {}
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Resized(size) = event {
                let scale = window.scale_factor().unwrap_or(1.0);
                let logical = size.to_logical::<f64>(scale);
                let _ = window.emit(
                    "catenary-resize",
                    json!({
                        "width": logical.width.to_string(),
                        "height": logical.height.to_string()
                    }),
                );
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(move |_app, event| {
            if let RunEvent::Exit = event {
                if let Some(pid) = exit_pid.lock().unwrap().take() {
                    kill_backend(pid);
                    println!("[catenary] backend killed");
                }
            }
        });
}
