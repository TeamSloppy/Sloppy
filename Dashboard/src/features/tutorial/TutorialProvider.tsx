import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { PROJECT_TUTORIAL_STORAGE_KEY, tutorialSteps, type TutorialStep } from "./tutorialSteps";

interface TutorialStoredState {
  completed?: boolean;
  skipped?: boolean;
}

interface TutorialContextValue {
  activeStep: TutorialStep | null;
  activeStepIndex: number;
  totalSteps: number;
  isActive: boolean;
  hasCompleted: boolean;
  hasSkipped: boolean;
  startTutorial: () => void;
  startTutorialFromOnboarding: () => void;
  nextStep: () => void;
  previousStep: () => void;
  skipTutorial: () => void;
  finishTutorial: () => void;
}

const TutorialContext = createContext<TutorialContextValue | null>(null);

function readStoredState(): TutorialStoredState {
  if (typeof window === "undefined") return {};
  try {
    const raw = window.localStorage.getItem(PROJECT_TUTORIAL_STORAGE_KEY);
    return raw ? (JSON.parse(raw) as TutorialStoredState) : {};
  } catch {
    return {};
  }
}

function writeStoredState(next: TutorialStoredState) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PROJECT_TUTORIAL_STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Browser-local tutorial state is best-effort only.
  }
}

export function TutorialProvider({ children }: { children: React.ReactNode }) {
  const [storedState, setStoredState] = useState<TutorialStoredState>(() => readStoredState());
  const [activeStepIndex, setActiveStepIndex] = useState(-1);

  const isActive = activeStepIndex >= 0 && activeStepIndex < tutorialSteps.length;

  const startTutorial = useCallback(() => {
    setActiveStepIndex(0);
  }, []);

  const startTutorialFromOnboarding = useCallback(() => {
    const current = readStoredState();
    setStoredState(current);
    if (!current.completed && !current.skipped) {
      setActiveStepIndex(0);
    }
  }, []);

  const finishTutorial = useCallback(() => {
    const next = { completed: true, skipped: false };
    writeStoredState(next);
    setStoredState(next);
    setActiveStepIndex(-1);
  }, []);

  const skipTutorial = useCallback(() => {
    const next = { completed: false, skipped: true };
    writeStoredState(next);
    setStoredState(next);
    setActiveStepIndex(-1);
  }, []);

  const nextStep = useCallback(() => {
    setActiveStepIndex((current) => {
      if (current < 0) return current;
      if (current >= tutorialSteps.length - 1) {
        const next = { completed: true, skipped: false };
        writeStoredState(next);
        setStoredState(next);
        return -1;
      }
      return current + 1;
    });
  }, []);

  const previousStep = useCallback(() => {
    setActiveStepIndex((current) => Math.max(0, current - 1));
  }, []);

  useEffect(() => {
    function handleStorage(event: StorageEvent) {
      if (event.key === PROJECT_TUTORIAL_STORAGE_KEY) {
        setStoredState(readStoredState());
      }
    }
    window.addEventListener("storage", handleStorage);
    return () => window.removeEventListener("storage", handleStorage);
  }, []);

  const value = useMemo<TutorialContextValue>(() => ({
    activeStep: isActive ? tutorialSteps[activeStepIndex] : null,
    activeStepIndex,
    totalSteps: tutorialSteps.length,
    isActive,
    hasCompleted: Boolean(storedState.completed),
    hasSkipped: Boolean(storedState.skipped),
    startTutorial,
    startTutorialFromOnboarding,
    nextStep,
    previousStep,
    skipTutorial,
    finishTutorial
  }), [
    activeStepIndex,
    finishTutorial,
    isActive,
    nextStep,
    previousStep,
    skipTutorial,
    startTutorial,
    startTutorialFromOnboarding,
    storedState.completed,
    storedState.skipped
  ]);

  return <TutorialContext.Provider value={value}>{children}</TutorialContext.Provider>;
}

export function useTutorial() {
  const context = useContext(TutorialContext);
  if (!context) {
    throw new Error("useTutorial must be used inside TutorialProvider");
  }
  return context;
}
