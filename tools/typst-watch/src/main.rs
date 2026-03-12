use notify::Watcher;

mod build;
mod error;
mod typst;

use crate::{
    build::{DST, ROOT, SRC, TEMPLATE_NAME, compile_all, compile_file},
    error::{Error, Result},
};


// -------------------------------- ------------------ -------------------------------- //
// -------------------------------- Entry point (main) -------------------------------- //
// -------------------------------- ------------------ -------------------------------- //

fn main() -> Result<(),> {
    let root = String::from(ROOT,);

    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info",),)
        .init();

    log::info!("--- Watcher started ---");
    log::info!("SRC: {}", root.clone() + "/" + SRC);
    log::info!("DST: {}", root.clone() + "/" + DST);

    log::info!("Performing initial build...");

    if let Err(err,) = compile_all() {
        log::error!("An error occured during initial build: [{}]", err);
    }

    log::info!("Initial build completed, setting up watcher...");

    let (sd, rc,) = std::sync::mpsc::channel();
    let mut watcher = notify::RecommendedWatcher::new(sd, notify::Config::default(),)?;

    watcher.watch(
        &std::path::Path::new(ROOT,).join(SRC,),
        notify::RecursiveMode::Recursive,
    )?;

    log::info!("Watching {}", root.clone() + "/" + SRC);

    for res in rc {
        match res {
            | Ok(event,) => {
                for path in event.paths {
                    if path.ends_with(TEMPLATE_NAME,) {
                        log::info!("Template changed, rebuilding all files...");

                        if let Err(err,) = compile_all() {
                            log::error!("An error occured during rebuild: [{}]", err);
                        }

                        continue;
                    }

                    match compile_file(&path,) {
                        | Ok(true,) => {
                            log::info!("Rebuilt file {:?}", path.file_name().unwrap())
                        },
                        | Ok(false,) => {},
                        | Err(err,) => {
                            log::error!("Failed to compile {:?}: {}", path, err)
                        },
                    }
                }
            },
            | Err(err,) => {
                log::error!("An error occured during the watch: {}", Error::from(err))
            },
        }
    }

    Ok((),)
}
