import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

function loadI18nSandbox(language = "en-US", languages = [language]) {
  const source = readFileSync(new URL("../Resources/i18n.js", import.meta.url), "utf8");
  const sandbox = {
    navigator: { language, languages },
    globalThis: {}
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return sandbox.SloppyI18n;
}

test("i18n selects supported locale from system language", () => {
  assert.equal(loadI18nSandbox("ru-RU").systemLocale(), "ru");
  assert.equal(loadI18nSandbox("zh-Hans-CN").systemLocale(), "zh");
  assert.equal(loadI18nSandbox("fr-FR").systemLocale(), "en");
});

test("i18n translates parameterized strings", () => {
  const i18n = loadI18nSandbox("ru-RU");

  assert.equal(i18n.t("askSloppy"), "Спросить Sloppy");
  assert.equal(i18n.t("accessibleTabs", { count: 3 }), "Доступных вкладок: 3");
  assert.equal(i18n.t("readWeb"), "Чтение web");
});

test("i18n falls back to English for missing locales", () => {
  const i18n = loadI18nSandbox("de-DE");

  assert.equal(i18n.t("askAboutPage"), "Ask about this page");
  assert.equal(i18n.t("missing.key"), "missing.key");
});
