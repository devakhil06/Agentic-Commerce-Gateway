{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({onEntrypointLoaded: async function (engineInitializer) {
  const runner = await engineInitializer.initializeEngine();
  document.getElementById('boot')?.remove();
  await runner.runApp();
}});
