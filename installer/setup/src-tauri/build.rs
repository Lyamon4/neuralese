fn main() {
    println!("cargo:rerun-if-env-changed=NEURALESE_APP_NAME");
    println!("cargo:rerun-if-env-changed=NEURALESE_GAME_EXE");
    println!("cargo:rerun-if-changed=app.manifest");
    println!("cargo:rerun-if-changed=icons/icon.ico");
    println!("cargo:rerun-if-changed=fonts/Inter.ttf");
    println!("cargo:rerun-if-changed=fonts/Montserrat.ttf");
    println!("cargo:rerun-if-changed=ui/minimize.svg");
    println!("cargo:rerun-if-changed=ui/close.svg");
    slint_build::compile("ui/app.slint").expect("failed to compile Slint UI");

    #[cfg(windows)]
    {
        let mut resource = winresource::WindowsResource::new();
        resource.set_icon("icons/icon.ico");
        resource.set("ProductName", "Neuralese Setup");
        resource.set("FileDescription", "Neuralese Setup");
        resource.set("CompanyName", "Neuralese");
        resource.set_manifest_file("app.manifest");
        resource.compile().expect("failed to compile Windows resources");
    }
}
