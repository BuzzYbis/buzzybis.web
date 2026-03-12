use dioxus::prelude::*;


// ---------------------------------- Types section ---------------------------------- //

pub type Result<T, E = Error,> = std::result::Result<T, E,>;


// ------------------------------- Enumerations section ------------------------------- //

#[derive(Debug, serde::Deserialize, serde::Serialize)]
#[serde(crate = "serde")]
pub enum Error {
    External { from: String, err: String, },
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_,>,) -> std::fmt::Result {
        match self {
            | Error::External { from, err, } => {
                write!(f, "Crate {} raised the error: {}", from, err)
            },
        }
    }
}

impl std::error::Error for Error {}

impl dioxus_fullstack::AsStatusCode for Error {
    fn as_status_code(&self,) -> StatusCode {
        match self {
            | Error::External { from, err, }
                if from == &String::from("dioxus server error",) =>
            {
                http::StatusCode::INTERNAL_SERVER_ERROR
            },
            | _ => http::StatusCode::NOT_FOUND,
        }
    }
}


impl From<std::io::Error,> for Error {
    fn from(value: std::io::Error,) -> Self {
        Self::External { from: String::from("std::io",), err: value.to_string(), }
    }
}

impl From<ServerFnError,> for Error {
    fn from(value: ServerFnError,) -> Self {
        Self::External {
            from: String::from("dioxus server error",),
            err:  value.to_string(),
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
impl From<lopdf::Error,> for Error {
    fn from(value: lopdf::Error,) -> Self {
        Self::External {
            from: String::from("pdf metadata parsing",),
            err:  value.to_string(),
        }
    }
}

impl From<std::string::FromUtf8Error,> for Error {
    fn from(value: std::string::FromUtf8Error,) -> Self {
        Self::External { from: String::from("utf8 error",), err: value.to_string(), }
    }
}
