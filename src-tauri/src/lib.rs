use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

use serde_json::json;
use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};
use tauri::{Emitter, Manager, Window};
use tauri_plugin_shell::process::CommandEvent;
use tauri_plugin_shell::ShellExt;

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
    let reload = MenuItemBuilder::with_id("reload", "Reload")
        .accelerator("CmdOrCtrl+R")
        .build(handle)?;
    let close_window = PredefinedMenuItem::close_window(handle, None)?;
    let quit = PredefinedMenuItem::quit(handle, Some("Quit Catenary"))?;

    let catenary = SubmenuBuilder::new(handle, "Catenary")
        .item(&quit)
        .build()?;
    let go = SubmenuBuilder::new(handle, "Go").item(&dashboard).build()?;
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

// Spawns the Elixir backend (a Burrito-wrapped release) as a sidecar and
// forwards its output to our logs.
fn start_backend(app: &tauri::AppHandle) {
    let handle = app.clone();
    std::thread::spawn(move || {
        let command = match handle.shell().sidecar("binaries/catenary-backend") {
            Ok(command) => command.arg("--no-halt"),
            Err(err) => {
                eprintln!("[catenary] unable to resolve the backend sidecar: {err}");
                return;
            }
        };

        match command.spawn() {
            Ok((mut rx, _child)) => {
                println!("[catenary] backend started");
                while let Some(event) = rx.blocking_recv() {
                    match event {
                        CommandEvent::Stdout(line) => {
                            println!("[catenary] {}", String::from_utf8_lossy(&line).trim_end())
                        }
                        CommandEvent::Stderr(line) => {
                            eprintln!("[catenary] {}", String::from_utf8_lossy(&line).trim_end())
                        }
                        _ => {}
                    }
                }
            }
            Err(err) => eprintln!("[catenary] failed to spawn the backend sidecar: {err}"),
        }
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
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![set_window_size])
        .setup(|app| {
            build_menu(app)?;
            start_backend(app.handle());

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
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
