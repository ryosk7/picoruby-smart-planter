// One PicoRuby VM per isolate, built while the Worker starts.
//
// The template's createWorker() builds and closes a VM for every request,
// which costs about 20 ms of CPU per request: over the Workers Free plan's
// 10 ms. Here the VM is built once at startup (counted against the 1 s
// startup limit instead) and every request is dispatched to it; dispatch()
// runs requests on one VM one at a time.
import { env } from "cloudflare:workers";
import createPicoRuby from "../generated/worker/runtime/picoruby-worker.js";
import wasm from "../generated/worker/runtime/picoruby-worker.wasm";
import app from "../generated/worker/app.bin";
import { cloudflareBindingTypes } from "../generated/worker/bindings.js";
import {
  closeRuntime,
  createCloudflareBindings,
  createRuntime,
  dispatch,
  RequestBodyTooLargeError,
} from "../generated/worker/runtime/runtime.js";

export { PicoRubyDurableObject } from "../generated/worker/runtime/index.js";

// Workers do not allow random values at startup, but Sinatra makes a default
// session secret with SecureRandom while it loads. This app uses no sessions,
// so only that startup call gets zero bytes; the real function is restored
// before any request runs.
async function withoutStartupRandom(build) {
  const getRandomValues = crypto.getRandomValues;
  crypto.getRandomValues = array => {
    try {
      return getRandomValues.call(crypto, array);
    } catch {
      return array.fill(0);
    }
  };
  try {
    return await build();
  } finally {
    crypto.getRandomValues = getRandomValues;
  }
}

async function startRuntime() {
  const bindings = createCloudflareBindings(env, cloudflareBindingTypes);
  return withoutStartupRandom(() => createRuntime(createPicoRuby, wasm, app, bindings));
}

let runtime = startRuntime();
await runtime;

export default {
  async fetch(request) {
    try {
      return await dispatch(await runtime, request);
    } catch (error) {
      console.error("PicoRuby Worker request failed", error);
      if (error instanceof RequestBodyTooLargeError) {
        return new Response("Request body too large", { status: 413 });
      }
      // A failure outside the Ruby app may leave the VM unusable: replace it
      // (this one is built inside a request, so it costs that request's CPU).
      const broken = runtime;
      runtime = startRuntime();
      runtime.catch(() => {});
      broken.then(closeRuntime).catch(() => {});
      return new Response("PicoRuby Worker runtime error", { status: 500 });
    }
  },
};
