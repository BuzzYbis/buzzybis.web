use crate::{
    error::{Error, Result},
    typst::compile_typst,
};


// -------------------------------- Constants section -------------------------------- //

pub const ROOT: &str = "./website";
pub const SRC: &str = "data";
pub const DST: &str = "public";
pub const TEMPLATE_NAME: &str = "template.typ";
const SUBMODULE: &str = "blogfiles";
const SUFFIX_PROJECT: &str = ".p.typ";
const SUFFIX_BLOG: &str = ".b.typ";


// -------------------------------- Functions section -------------------------------- //

pub fn compile_file(path: &std::path::PathBuf,) -> Result<bool,> {
    if let Some((dst_d, title,),) = get_route(path,)? {
        let dst_d = std::path::Path::new(ROOT,).join(DST,).join(dst_d,);
        if !dst_d.exists() {
            std::fs::create_dir_all(&dst_d,)?;
        }

        let submodule_path = std::path::Path::new(ROOT,).join(SRC,).join(SUBMODULE,);
        let compilation_root = if path.starts_with(&submodule_path,) {
            submodule_path
        } else {
            std::path::Path::new(ROOT,).join(SRC,).to_path_buf()
        };

        let dst_pdf = dst_d.join(format!("{}.pdf", title),);
        compile_typst(path, &dst_pdf, &compilation_root,)?;

        Ok(true,)
    } else {
        Ok(false,)
    }
}

pub fn compile_all() -> Result<(),> {
    let root = std::path::Path::new(ROOT,).join(SRC,);
    for entry in walkdir::WalkDir::new(&root,) {
        let entry = entry?;
        let path = entry.into_path();

        match compile_file(&path,) {
            | Ok(true,) => {
                log::info!("File {:?} as been builded", path.file_name().unwrap())
            },
            | Ok(false,) => {},
            | Err(err,) => {
                log::error!("Failed to compile {:?}: {}", path, err)
            },
        }
    }

    Ok((),)
}

fn get_route(path: &std::path::PathBuf,) -> Result<Option<(&'static str, String,),>,> {
    let name = path
        .file_name()
        .ok_or(Error::Build { msg: "Invalid file in data", },)?
        .to_str()
        .ok_or(Error::Build { msg: "Invalid file in data", },)?;
    if let Some(slug,) = name.strip_suffix(SUFFIX_PROJECT,) {
        Ok(Some(("projects", slug.to_string(),),),)
    } else if let Some(slug,) = name.strip_suffix(SUFFIX_BLOG,) {
        Ok(Some(("blogposts", slug.to_string(),),),)
    } else {
        Ok(None,)
    }
}
