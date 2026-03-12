// ---------------------------------- Types section ---------------------------------- //

pub type Result<T, E = Error,> = std::result::Result<T, E,>;


// ------------------------------- Enumerations section ------------------------------- //

#[derive(Debug)]
pub enum Error {
    Build { msg: &'static str, },
    External { from: &'static str, err: String, },
    Typst { msg: String, },
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_,>,) -> std::fmt::Result {
        match self {
            | Error::Build { msg, } => {
                write!(f, "An error occured during build operation: {}", msg)
            },
            | Error::External { from, err, } => {
                write!(f, "Crate {} raised the error: {}", from, err)
            },
            | Error::Typst { msg, } => write!(f, "Typst compilation raised: {}", msg),
        }
    }
}

impl std::error::Error for Error {}

impl From<notify::Error,> for Error {
    fn from(value: notify::Error,) -> Self {
        Self::External { from: "notify", err: value.to_string(), }
    }
}

impl From<std::io::Error,> for Error {
    fn from(value: std::io::Error,) -> Self {
        Self::External { from: "std::io", err: value.to_string(), }
    }
}

impl From<walkdir::Error,> for Error {
    fn from(value: walkdir::Error,) -> Self {
        Self::External { from: "walkdir", err: value.to_string(), }
    }
}
