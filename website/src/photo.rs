use dioxus::prelude::*;


// -------------------------------- Functions section -------------------------------- //

#[component]
pub fn PhotoHome() -> Element {
    rsx! { h1 { "Welcome to Photo" } }
}

#[component]
pub fn PhotoAbout() -> Element {
    rsx! { h1 { "Welcome to Photo About" } }
}

#[component]
pub fn Portfolio() -> Element {
    rsx! { h1 { "Welcome to Portfolio" } }
}

#[component]
pub fn Gallery(category: String,) -> Element {
    rsx! { h1 { "Welcome to a Gallery" } }
}
