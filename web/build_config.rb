require "picoruby/cloudflare/build"

MRuby::CrossBuild.new("worker") do |conf|
  # Worker runtime (picoruby-cloudflare-worker-wasm 0.10.0) and mruby-rack use
  # the revisions pinned by picoruby-cloudflare-template 0.2.1.
  conf.cloudflare_worker!

  # Sinatra on PicoRuby (the same mrbgems as examples/d1-todo), pinned to
  # commits so that a later build reproduces this one.
  conf.gem github: "udzura/mruby-mustermann",
           checksum_hash: "acc29b7a28721474ef07d40a6263a4806855fcd5"
  conf.gem github: "udzura/picoruby-sinatra-covers",
           checksum_hash: "70e96fc81153402b54c27bceb385bd9306717697"

  conf.worker_export(
    app: "app.rb",
    output_dir: "generated/worker",
    wrangler_config: "wrangler.jsonc",
    environment: ENV["CLOUDFLARE_ENV"],
    project_root: __dir__,
  )
end
