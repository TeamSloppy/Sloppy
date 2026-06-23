(function installSloppyI18n(root) {
  const dictionaries = {
    en: {
      agent: "Agent",
      askAboutPage: "Ask about this page",
      askSelection: "Ask Sloppy about selection",
      askSloppy: "Ask Sloppy",
      assistant: "Assistant",
      attachFile: "Attach file",
      attachScreenshot: "Attach screenshot",
      close: "Close",
      closeSessions: "Close sessions",
      closeSettings: "Close settings",
      defaultModel: "Default model",
      defaultModelSubtitle: "Use the agent default model",
      defineSelection: "Define the selected text.",
      done: "done",
      downloadSloppy: "Download Sloppy",
      factCheckSelection: "Fact check the selected text.",
      loadingRecentSessions: "Loading recent sessions...",
      loadingSessions: "Loading sessions...",
      model: "Model",
      newSession: "New session",
      noRecentSessions: "No recent sessions.",
      noSelection: "No selection",
      noSelectedText: "No selected text.",
      openFullscreenChat: "Open full-screen chat",
      openSloppyAssistant: "Open Sloppy assistant",
      readFile: "Read file",
      readWeb: "Read web",
      saveMemory: "Save memory",
      searchWeb: "Search web",
      selectedChars: "{count} selected chars",
      selectedSession: "Selected session",
      send: "Send",
      sending: "Sending...",
      sessions: "Sessions",
      sessionsUnavailable: "Sessions unavailable.",
      settings: "Settings",
      summarizePage: "Summarize page",
      summarizePageContextMenu: "Summary Page",
      summarizePagePrompt: "Summarize this page. Focus on the main points and any actionable details.\n\nUse the Safari page context attached to this message. Do not use web.fetch for this page URL; it may not have the user's browser session, cookies, or access.",
      summarizeSelection: "Summarize the selected text.",
      thinking: "Thinking",
      toolCall: "Tool call",
      translateSelection: "Translate the selected text.",
      voiceMode: "Voice mode",
      voiceModeFailed: "Voice mode failed.",
      voiceLanguage: "Voice language",
      voiceLanguageAuto: "Auto",
      voiceLanguageEnglish: "English",
      voiceLanguageRussian: "Russian",
      voiceLanguageChinese: "Chinese",
      voiceSettings: "Voice settings",
      writeFile: "Write file",
      you: "You",
      accessibleTabs: "{count} accessible tabs"
    },
    ru: {
      agent: "Агент",
      askAboutPage: "Спросить об этой странице",
      askSelection: "Спросить Sloppy о выделении",
      askSloppy: "Спросить Sloppy",
      assistant: "Ассистент",
      attachFile: "Прикрепить файл",
      attachScreenshot: "Прикрепить скриншот",
      close: "Закрыть",
      closeSessions: "Закрыть сессии",
      closeSettings: "Закрыть настройки",
      defaultModel: "Модель по умолчанию",
      defaultModelSubtitle: "Использовать модель агента по умолчанию",
      defineSelection: "Дай определение выделенному тексту.",
      done: "готово",
      downloadSloppy: "Скачать Sloppy",
      factCheckSelection: "Проверь факты в выделенном тексте.",
      loadingRecentSessions: "Загружаю последние сессии...",
      loadingSessions: "Загружаю сессии...",
      model: "Модель",
      newSession: "Новая сессия",
      noRecentSessions: "Последних сессий нет.",
      noSelection: "Нет выделения",
      noSelectedText: "Нет выделенного текста.",
      openFullscreenChat: "Открыть чат на весь экран",
      openSloppyAssistant: "Открыть ассистента Sloppy",
      readFile: "Чтение файла",
      readWeb: "Чтение web",
      saveMemory: "Сохранение памяти",
      searchWeb: "Поиск в web",
      selectedChars: "Выделено символов: {count}",
      selectedSession: "Выбранная сессия",
      send: "Отправить",
      sending: "Отправляю...",
      sessions: "Сессии",
      sessionsUnavailable: "Сессии недоступны.",
      settings: "Настройки",
      summarizePage: "Кратко о странице",
      summarizePageContextMenu: "Кратко о странице",
      summarizePagePrompt: "Суммируй эту страницу. Сфокусируйся на главных тезисах и полезных деталях.\n\nИспользуй контекст Safari-страницы, приложенный к этому сообщению. Не используй web.fetch для URL этой страницы: у него может не быть браузерной сессии пользователя, cookies или доступа.",
      summarizeSelection: "Суммируй выделенный текст.",
      thinking: "Думаю",
      toolCall: "Технический вызов",
      translateSelection: "Переведи выделенный текст.",
      voiceMode: "Голосовой режим",
      voiceModeFailed: "Голосовой режим не сработал.",
      voiceLanguage: "Язык общения",
      voiceLanguageAuto: "Авто",
      voiceLanguageEnglish: "Английский",
      voiceLanguageRussian: "Русский",
      voiceLanguageChinese: "Китайский",
      voiceSettings: "Настройки голоса",
      writeFile: "Запись файла",
      you: "Вы",
      accessibleTabs: "Доступных вкладок: {count}"
    },
    zh: {
      agent: "智能体",
      askAboutPage: "询问此页面",
      askSelection: "向 Sloppy 询问所选内容",
      askSloppy: "询问 Sloppy",
      assistant: "助手",
      attachFile: "添加文件",
      attachScreenshot: "添加截图",
      close: "关闭",
      closeSessions: "关闭会话",
      closeSettings: "关闭设置",
      defaultModel: "默认模型",
      defaultModelSubtitle: "使用智能体的默认模型",
      defineSelection: "解释所选文本。",
      done: "完成",
      downloadSloppy: "下载 Sloppy",
      factCheckSelection: "核查所选文本的事实。",
      loadingRecentSessions: "正在加载最近会话...",
      loadingSessions: "正在加载会话...",
      model: "模型",
      newSession: "新会话",
      noRecentSessions: "没有最近会话。",
      noSelection: "未选择",
      noSelectedText: "没有选中文本。",
      openFullscreenChat: "打开全屏聊天",
      openSloppyAssistant: "打开 Sloppy 助手",
      readFile: "读取文件",
      readWeb: "读取网页",
      saveMemory: "保存记忆",
      searchWeb: "搜索网页",
      selectedChars: "已选择 {count} 个字符",
      selectedSession: "已选会话",
      send: "发送",
      sending: "正在发送...",
      sessions: "会话",
      sessionsUnavailable: "会话不可用。",
      settings: "设置",
      summarizePage: "总结页面",
      summarizePageContextMenu: "总结页面",
      summarizePagePrompt: "总结此页面。请关注主要观点和可执行的细节。\n\n使用此消息附带的 Safari 页面上下文。不要对这个页面 URL 使用 web.fetch；它可能没有用户的浏览器会话、cookies 或访问权限。",
      summarizeSelection: "总结所选文本。",
      thinking: "思考中",
      toolCall: "技术调用",
      translateSelection: "翻译所选文本。",
      voiceMode: "语音模式",
      voiceModeFailed: "语音模式失败。",
      voiceLanguage: "语音语言",
      voiceLanguageAuto: "自动",
      voiceLanguageEnglish: "英语",
      voiceLanguageRussian: "俄语",
      voiceLanguageChinese: "中文",
      voiceSettings: "语音设置",
      writeFile: "写入文件",
      you: "你",
      accessibleTabs: "{count} 个可访问标签页"
    }
  };

  function normalizeLocale(value) {
    const language = String(value || "").toLowerCase();
    if (language.startsWith("ru")) {
      return "ru";
    }
    if (language.startsWith("zh")) {
      return "zh";
    }
    return "en";
  }

  function systemLocale(navigatorLike = root.navigator) {
    const languages = Array.isArray(navigatorLike?.languages) ? navigatorLike.languages : [];
    return normalizeLocale(languages[0] || navigatorLike?.language || "en");
  }

  function format(template, params = {}) {
    return String(template || "").replace(/\{([a-zA-Z0-9_]+)\}/g, (_match, name) => String(params[name] ?? ""));
  }

  function t(key, params = {}, locale = systemLocale()) {
    const dictionary = dictionaries[normalizeLocale(locale)] || dictionaries.en;
    return format(dictionary[key] || dictionaries.en[key] || key, params);
  }

  root.SloppyI18n = {
    dictionaries,
    normalizeLocale,
    systemLocale,
    t
  };
})(globalThis);
