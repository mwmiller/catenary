// We import the CSS which is extracted to its own file by esbuild.
// Remove this line if you add a your own CSS build pipeline (e.g postcss).
//
// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "./vendor/some-package.js"
//
// Alternatively, you can `npm install some-package` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Bridges native (Tauri) menu and window events with the LiveView.
let MenuBridge = {
  mounted() {
    this.el.addEventListener("phx:window-init", (e) => {
      const {width, height} = e.detail
      if (window.__TAURI__) {
        window.__TAURI__.core.invoke("set_window_size", {width, height})
      }
    })

    if (window.__TAURI__) {
      window.__TAURI__.event.listen("catenary-menu", (event) => {
        this.pushEvent("menu", event.payload)
      })

      window.__TAURI__.event.listen("catenary-resize", (event) => {
        this.pushEvent("window-resize", event.payload)
      })
    }

    this.handleEvent("export-save", ({content, filename}) => {
      if (window.__TAURI__) {
        window.catenarySave(content, filename)
      } else {
        const blob = new Blob([content], {type: "application/octet-stream"})
        const url = URL.createObjectURL(blob)
        const a = document.createElement("a")
        a.href = url
        a.download = filename
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        URL.revokeObjectURL(url)
      }
    })
  }
}

window.catenarySave = async function(content, defaultName) {
  if (!window.__TAURI__) return null
  const { save } = window.__TAURI__.dialog
  const path = await save({ defaultPath: defaultName })
  if (!path) return null
  await window.__TAURI__.core.invoke("write_file", { path, content })
  return path
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {MenuBridge}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
