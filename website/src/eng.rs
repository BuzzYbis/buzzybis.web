use dioxus::prelude::*;

use crate::{
    Route,
    get_file_list::{fetch_blog_posts, fetch_project_posts},
    statics::{
        about::AboutHtml,
        svg::{EmailIcon, GitHubIcon, LinkedinIcon, PdfIcon, TwitterIcon},
    },
};


// -------------------------------- Constants section -------------------------------- //

const VIEWER_CSS: Asset = asset!("/assets/viewer.css");
const LISTS_CSS: Asset = asset!("/assets/lists.css");
const HOME_CSS: Asset = asset!("/assets/home.css");


// -------------------------------- Functions section -------------------------------- //

#[component]
pub fn EngHome() -> Element {
    rsx! {
        document::Stylesheet { href: HOME_CSS }
        document::Stylesheet { href: "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.3.0/font/bootstrap-icons.css" }

        div{
            class: "master",

            div {
                class: "home-container",

                div { class: "profile-box",
                    h1 { class: "profile-name", "Ugo \'BuzzY_\' Gosso" }
                    h2 { class: "profile-work", "SWE @ Airbus Defence & Space" }
                    p { class: "profile-motto", "\"For type safety and performance!\"" }
                }

                // Box 2: Text Box
                div { class: "content-box text-box",
                    AboutHtml {}
                }
            }

            div { class: "links-box",
                a { href: "https://github.com/BuzzYbis", target: "_blank", class: "link-btn", title: "Github",
                    GitHubIcon {}
                }

                a { href: "https://www.linkedin.com/in/ugo-gosso", target: "_blank", class: "link-btn", title: "Linkedin",
                    LinkedinIcon {}
                }

                a { href: "https://x.com/BuzzYbis", class: "link-btn", title: "Twitter",
                    TwitterIcon {}
                }

                a { href: "mailto:contact@buzzybis.com", class: "link-btn", title: "Email",
                    EmailIcon {}
                }

                a { href: "/CV_Ugo_Gosso_SWE.pdf", class: "link-btn", title: "Download CV", download: "CV_Ugo_Gosso_SWE.pdf",
                    PdfIcon {}
                    p { "Download CV" }
                }
            }
        }
    }
}

#[component]
pub fn Projects() -> Element {
    let posts_req = use_resource(|| async move { fetch_project_posts().await },);

    rsx! {
        document::Stylesheet { href: LISTS_CSS }

        h1 { style: "text-align: center", "Project list" }

        match &*posts_req.read() {
            Some(Ok(posts)) => rsx! {
                div {
                    class: "entry-list",

                    for entry in posts {
                        Link {
                            class: "entry-box",
                            to: Route::ProjectDetail { title: entry.file_name.clone() },

                            div {
                                class: "metadata",

                                div {
                                    if let Some(tags) = &entry.keywords {
                                        for kw in tags {
                                            span { class: "tag-pill", "{kw}" }
                                        }
                                    }
                                }

                                p { "{entry.date_display}" }
                            }

                            div {
                                class: "title",

                                p { style: "font-weight: bold", "{entry.title}:" }
                                p { "{entry.description}" }
                            }
                        }
                    }
                }
            },
            Some(Err(e)) => rsx! {
                p { style: "color: red;", "Failed to load posts: {e}" }
            },
            None => rsx! {
                p { "Loading posts..." }
            }
        }
    }
}

#[component]
pub fn ProjectDetail(title: String,) -> Element {
    rsx! {
        EntryDisplay {
            src: "/projects/{title}.pdf",
            to: Route::Projects {},
            text: "← Back to Projects"
        }
    }
}

#[component]
pub fn BlogIndex() -> Element {
    let posts_req = use_resource(|| async move { fetch_blog_posts().await },);

    rsx! {
        document::Stylesheet { href: LISTS_CSS }

        h1 { style: "text-align: center", "Blog entry list" }

        match &*posts_req.read() {
            Some(Ok(posts)) => rsx! {
                div {
                    class: "entry-list",

                    for entry in posts {
                        Link {
                            class: "entry-box",
                            to: Route::BlogPost { title: entry.file_name.clone() },

                            div {
                                class: "metadata",

                                div {
                                    if let Some(tags) = &entry.keywords {
                                        for kw in tags {
                                            span { class: "tag-pill", "{kw}" }
                                        }
                                    }
                                }

                                p { "{entry.date_display}" }
                            }

                            div {
                                class: "title",

                                p { style: "font-weight: bold", "{entry.title}:" }
                                p { "{entry.description}" }
                            }
                        }
                    }
                }
            },
            Some(Err(e)) => rsx! {
                p { style: "color: red;", "Failed to load posts: {e}" }
            },
            None => rsx! {
                p { "Loading posts..." }
            }
        }
    }
}

#[component]
pub fn BlogPost(title: String,) -> Element {
    rsx! {
        EntryDisplay {
            src: "/blogposts/{title}.pdf",
            to: Route::BlogIndex {},
            text: "← Back to Blog"
        }
    }
}

#[component]
fn EntryDisplay(src: String, to: Route, text: String,) -> Element {
    rsx! {
        document::Stylesheet { href: VIEWER_CSS }

        div { class: "reader-container",
            div { class: "reader-header",
                Link {
                    to: to,
                    class: "back-button",
                    "{text}"
                }
            }

            div { class: "pdf-frame",
                iframe {
                    src: src,
                    class: "pdf-iframe",
                    title: "PDF Viewer"
                }
            }
        }
    }
}
