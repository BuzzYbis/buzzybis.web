use dioxus::prelude::*;


mod eng;
mod error;
mod get_file_list;
mod photo;

use crate::{
    eng::{BlogIndex, BlogPost, EngHome, ProjectDetail, Projects},
    photo::{Gallery, PhotoAbout, PhotoHome, Portfolio},
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

    #[nest("/photo")]
        #[layout(PhotoLayout)]
            #[route("/")]
            PhotoHome {},
            #[route("/about")]
            PhotoAbout {},
            #[route("/portfolio")]
            Portfolio {},
            #[route("/gallery/:category")]
            Gallery { category: String },
        #[end_layout]
    #[end_nest]

    #[route("/under_construction")]
    UnderConstruction {},
    #[route("/:..route")]
    NotFound { route: Vec<String> },
}


// -------------------------------- Functions section -------------------------------- //

#[component]
fn App() -> Element {
    rsx! {
        // Global CSS injection
        document::Stylesheet { href: asset!("/assets/main.css") }
        Router::<Route> {}
    }
}


#[component]
fn EngLayout() -> Element {
    rsx! {
        div { class: "eng-layout",
            nav { class: "eng-sidebar",
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
fn PhotoLayout() -> Element {
    rsx! {
        div { class: "photo-layout",
            // // Top Header
            // nav { class: "photo-header",
            //     div { class: "photo-brand",
            //         Link { to: Route::PhotoHome {}, "Ugo Gosso photography" }
            //     }

            //     div { class: "photo-nav-links",
            //         Link { to: Route::Portfolio {}, "Portfolio" }
            //         Link { to: Route::Gallery { category: "street".into() }, "Street" }
            //         Link { to: Route::Gallery { category: "sport".into() }, "Sport" }
            //     }

            //     div { class: "photo-context-switch",
            //         Link {
            //             to: Route::EngHome {},
            //             class: "switch-link",
            //             "Goto engineering side"
            //         }
            //     }
            // }
            // // Content Outlet
            // main { class: "photo-content", Outlet::<Route> {} }
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
