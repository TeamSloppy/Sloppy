type FontFaceSetLike = {
  load?: (font: string, text?: string) => Promise<unknown>;
  check?: (font: string, text?: string) => boolean;
};

type IconFontDocument = {
  documentElement: {
    classList: {
      add: (className: string) => void;
    };
  };
  fonts?: FontFaceSetLike;
};

const iconsReadyClass = "icons-ready";
const materialSymbolsFont = "20px 'Material Symbols Rounded'";
const materialSymbolsProbe = "home";

export async function markMaterialSymbolsReady(doc: IconFontDocument = document): Promise<boolean> {
  const fonts = doc.fonts;

  if (!fonts) {
    doc.documentElement.classList.add(iconsReadyClass);
    return false;
  }

  try {
    await fonts.load?.(materialSymbolsFont, materialSymbolsProbe);
  } catch {
    // Fall through to check(); Safari can still report a usable face after a load error.
  }

  if (fonts.check?.(materialSymbolsFont, materialSymbolsProbe)) {
    doc.documentElement.classList.add(iconsReadyClass);
    return true;
  }

  return false;
}
