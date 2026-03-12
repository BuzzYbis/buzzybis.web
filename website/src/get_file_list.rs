use dioxus::prelude::*;

use crate::error::Result;


// -------------------------------- Structures section -------------------------------- //

#[derive(Debug, serde::Deserialize, serde::Serialize)]
#[serde(crate = "serde")]
pub struct EntryMetadata {
    pub file_name:    String,
    pub title:        String,
    pub date_display: String,
    pub description:  String,
    pub keywords:     Option<Vec<String,>,>,
}


// -------------------------------- Functions section -------------------------------- //

#[server]
pub async fn fetch_blog_posts() -> Result<Vec<EntryMetadata,>,> {
    let mut posts = Vec::new();

    let dir_path = std::path::Path::new("public/blogposts",);

    if let Ok(entries,) = std::fs::read_dir(dir_path,) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map_or(false, |ext| ext == "pdf",) {
                let entry = get_pdf_info(&path,)?;
                posts.push(entry,);
            }
        }
    }

    posts.sort_by(|a, b| b.date_display.cmp(&a.date_display,),);

    Ok(posts,)
}

#[server]
pub async fn fetch_project_posts() -> Result<Vec<EntryMetadata,>,> {
    let mut posts = Vec::new();

    let dir_path = std::path::Path::new("public/projects",);

    if let Ok(entries,) = std::fs::read_dir(dir_path,) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map_or(false, |ext| ext == "pdf",) {
                let entry = get_pdf_info(&path,)?;
                posts.push(entry,);
            }
        }
    }

    posts.sort_by(|a, b| b.date_display.cmp(&a.date_display,),);

    Ok(posts,)
}

#[cfg(not(target_arch = "wasm32"))]
fn get_pdf_info(path: &std::path::Path,) -> Result<EntryMetadata,> {
    let file_name = String::from(path.file_stem().unwrap().to_str().unwrap(),);

    let doc = lopdf::Document::load(path,)?;

    let info_dict = doc
        .trailer
        .get(b"Info",)
        .and_then(|obj| obj.as_reference(),)
        .and_then(|id| doc.get_dictionary(id,),)?;

    let extract_field = |key: &[u8]| -> String {
        info_dict
            // 1. Convert Result<&Object, Error> to Option<&Object>
            .get(key)
            .ok()
            .and_then(|obj| match obj {
                lopdf::Object::String(bytes, _) => {
                    // 2. Check for the UTF-16BE BOM (0xFE, 0xFF) that Typst uses
                    if bytes.starts_with(&[0xFE, 0xFF]) {
                        // Optimisation: Decode directly from UTF-16 bytes
                        let u16_words: Vec<u16> = bytes[2..]
                            .chunks_exact(2)
                            .map(|chunk| u16::from_be_bytes([chunk[0], chunk[1]]))
                            .collect();
                        String::from_utf16(&u16_words).ok()
                    } else {
                        // Fallback to UTF-8
                        String::from_utf8(bytes.to_vec()).ok()
                    }
                }
                _ => None,
            })
            // 3. Option::unwrap_or_else takes no arguments
            .unwrap_or_else(|| "Unknown".to_string())
    };

    let title = extract_field(b"Title",);
    let description = extract_field(b"Subject",); // "Description" maps to "Subject" in PDF
    let raw_date = extract_field(b"CreationDate",);

    let raw_keywords = extract_field(b"Keywords",);
    let keywords = if raw_keywords == "Unknown" || raw_keywords.trim().is_empty() {
        None
    } else {
        Some(
            raw_keywords
                .split(',',)
                .map(|s| s.trim().to_string().to_uppercase(),)
                .filter(|s| !s.is_empty(),)
                .collect(),
        )
    };


    Ok(EntryMetadata {
        file_name,
        title,
        date_display: format_pdf_date(&raw_date,),
        description,
        keywords,
    },)
}

fn format_pdf_date(raw: &str,) -> String {
    let d = raw.strip_prefix("D:",).unwrap_or(raw,);
    if d.len() >= 8 {
        let year = &d[0..4];
        let month_num = &d[4..6];
        let day = &d[6..8];

        return format!("{}-{}-{}", year, month_num, day);
    }
    "Unknown Date".to_string()
}
