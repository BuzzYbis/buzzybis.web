use crate::error::{Error, Result};


// -------------------------------- Functions section -------------------------------- //

pub fn compile_typst(
    input: &std::path::Path,
    output: &std::path::Path,
    root: &std::path::Path,
) -> Result<(),> {
    log::info!(
        "Compiling: {:?} -> {:?}",
        input.file_name().unwrap(),
        output.file_name().unwrap()
    );

    let result = std::process::Command::new("typst",)
        .arg("compile",)
        .arg("--root",)
        .arg(root,)
        .arg(input,)
        .arg(&output,)
        .output();

    match result {
        | Ok(output,) => {
            if output.status.success() {
                Ok((),)
            } else {
                let error_msg = String::from_utf8_lossy(&output.stderr,);

                log::error!(
                    "Typst Compilation Failed for {:?}:\n{}",
                    input,
                    error_msg.trim()
                );

                Err(Error::Typst {
                    msg: format!(
                        "CLI exited with status {}: {}",
                        output.status,
                        error_msg.trim()
                    ),
                },)
            }
        },
        | Err(e,) => {
            log::error!("Failed to execute 'typst' binary. Is it installed and in PATH?");
            Err(Error::Typst { msg: format!("Failed to spawn process: {}", e), },)
        },
    }
}
