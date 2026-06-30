/** Semantic application version. @const {string} */
const APP_VERSION = APP.VERSION;

/**
 * Returns application release information.
 * @return {{name: string, version: string, runtime: string}}
 */
function getVersion() {
  return Object.freeze({name: APP.NAME, version: APP_VERSION, runtime: 'V8'});
}
