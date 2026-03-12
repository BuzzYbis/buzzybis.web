use dioxus::prelude::*;

mod eng;
mod error;
mod get_file_list;
mod statics;

use crate::{
    eng::{BlogIndex, BlogPost, EngHome, ProjectDetail, Projects},
    statics::svg::SideBarIcon,
};


// -------------------------------- Constants section -------------------------------- //

const FAVICON: Asset = asset!("/assets/favicon.ico");
const MAIN_CSS: Asset = asset!("/assets/main.css");


// ------------------------------- Enumerations section ------------------------------- //

#[derive(Debug, Clone, Routable, PartialEq)]
#[rustfmt::skip]
enum Route {
    #[layout(EngLayout)]
        #[route("/")]
        EngHome {},
        #[nest("/projects")]
            #[route("/")]
            Projects {},
            #[route("/:title")]
            ProjectDetail { title: String },
        #[end_nest]
        #[nest("/blogposts")]
            #[route("/")]
            BlogIndex {},
            #[route("/:title")]
            BlogPost { title: String },
        #[end_nest]
    #[end_layout]

    #[route("/under_construction")]
    UnderConstruction {},
    #[route("/:..route")]
    NotFound { route: Vec<String> },
}


// -------------------------------- Functions section -------------------------------- //

#[component]
fn App() -> Element {
    rsx! {
        document::Link { rel: "icon", href: FAVICON }
        document::Stylesheet { href: MAIN_CSS }
        Router::<Route> {}
    }
}


#[component]
fn EngLayout() -> Element {
    let mut is_collapsed = use_signal(|| false,);

    rsx! {
        div { class: "eng-layout",
            button {
                class: if is_collapsed() { "toggle-btn collapsed" } else { "toggle-btn" },
                
                onclick: move |_| is_collapsed.toggle(),
                SideBarIcon {}
            }

            nav {
                class: if is_collapsed() { "eng-sidebar collapsed" } else { "eng-sidebar" },

                Link {
                    class: "eng-brand",
                    to: Route::EngHome {}, "BuzzY_"
                }

                div { class: "eng-nav-list",
                    Link { to: Route::EngHome {}, "Home" }
                    Link { to: Route::Projects {}, "Projects" }
                    Link { to: Route::BlogIndex {}, "Blog" } // Added Blog Link
                }

                Link {
                    to: Route::UnderConstruction {},
                    class: "context-switch-btn",
                    "Go to photography side"
                }

                Link {
                    style: "text-decoration: none; color: black; margin-top: auto; align-self: center",
                    to: "mailto:contact@buzzybis.com", "contact@buzzybis.com"
                }
            }
            
            main { class: "eng-content",
                Outlet::<Route> {}
            }
        }
    }
}

#[component]
fn UnderConstruction() -> Element {
    rsx! {
        div { class: "p-10",
            h1 { "Under construciton" }
            p { "The requested page is under construction, come back later to see it.." }
            Link { to: Route::EngHome {}, "Get back home" }
        }
    }
}

#[component]
fn NotFound(route: Vec<String,>,) -> Element {
    rsx! {
        div { class: "p-10",
            h1 { "404 - That's an error" }
            p { "The requested URl {route:?}, was is nowhere to be found on this website." }
            Link { to: Route::EngHome {}, "Get back home" }
        }
    }
}


// -------------------------------- ------------------ -------------------------------- //
// -------------------------------- Entry point (main) -------------------------------- //
// -------------------------------- ------------------ -------------------------------- //

fn main() {
    dioxus_logger::init(dioxus_logger::tracing::Level::INFO,)
        .expect("failed to init logger",);
    dioxus_logger::tracing::info!("Initialising website...");

    dioxus::launch(App,);
}
