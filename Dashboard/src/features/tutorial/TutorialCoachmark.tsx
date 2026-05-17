import React, { useEffect, useMemo, useState } from "react";
import { useTutorial } from "./TutorialProvider";

interface TutorialCoachmarkProps {
  hasProjects: boolean;
}

interface TargetBox {
  top: number;
  left: number;
  width: number;
  height: number;
}

function findTargetBox(targetId?: string): TargetBox | null {
  if (!targetId || typeof document === "undefined") return null;
  const element = document.querySelector(`[data-tour-id="${targetId}"]`) as HTMLElement | null;
  if (!element) return null;
  const rect = element.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return null;
  return {
    top: rect.top,
    left: rect.left,
    width: rect.width,
    height: rect.height
  };
}

export function TutorialCoachmark({ hasProjects }: TutorialCoachmarkProps) {
  const {
    activeStep,
    activeStepIndex,
    totalSteps,
    previousStep,
    nextStep,
    skipTutorial,
    finishTutorial
  } = useTutorial();
  const [targetBox, setTargetBox] = useState<TargetBox | null>(null);

  useEffect(() => {
    if (!activeStep?.targetId || !hasProjects) {
      setTargetBox(null);
      return;
    }

    let frame = 0;
    const update = () => setTargetBox(findTargetBox(activeStep.targetId));
    frame = window.requestAnimationFrame(update);
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);

    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("resize", update);
      window.removeEventListener("scroll", update, true);
    };
  }, [activeStep?.targetId, hasProjects]);

  const panelBody = useMemo(() => {
    if (!activeStep) return "";
    return !hasProjects && activeStep.emptyProjectBody ? activeStep.emptyProjectBody : activeStep.body;
  }, [activeStep, hasProjects]);

  if (!activeStep) {
    return null;
  }

  const isFirst = activeStepIndex <= 0;
  const isLast = activeStepIndex >= totalSteps - 1;
  const highlightVisible = Boolean(targetBox && hasProjects);

  return (
    <>
      {highlightVisible && targetBox ? (
        <div
          className="tutorial-highlight"
          aria-hidden="true"
          style={{
            top: targetBox.top - 6,
            left: targetBox.left - 6,
            width: targetBox.width + 12,
            height: targetBox.height + 12
          }}
        />
      ) : null}
      <section className="tutorial-coachmark" aria-live="polite" aria-label="Dashboard tutorial">
        <div className="tutorial-coachmark-topline">
          <span className="tutorial-kicker">Guided tips</span>
          <span className="tutorial-progress">{activeStepIndex + 1} / {totalSteps}</span>
        </div>
        <h2>{activeStep.title}</h2>
        <p>{panelBody}</p>
        {!hasProjects && activeStep.route.section === "projects" ? (
          <div className="tutorial-empty-hint">
            No project is open yet — use New Project, then replay or continue the tour.
          </div>
        ) : null}
        {activeStep.targetId && hasProjects && !highlightVisible ? (
          <div className="tutorial-empty-hint">
            This tip is still useful, but the target is not visible on the current viewport.
          </div>
        ) : null}
        <div className="tutorial-actions">
          <button type="button" className="tutorial-secondary" onClick={previousStep} disabled={isFirst}>
            Back
          </button>
          <button type="button" className="tutorial-secondary" onClick={skipTutorial}>
            Skip
          </button>
          <button type="button" className="tutorial-primary" onClick={isLast ? finishTutorial : nextStep}>
            {isLast ? "Finish" : "Next"}
          </button>
        </div>
      </section>
    </>
  );
}
