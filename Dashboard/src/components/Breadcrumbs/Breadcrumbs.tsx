import React from "react";
import "./Breadcrumbs.css";

export interface BreadcrumbItem {
    id: string;
    label: string;
    onClick?: () => void;
}

export interface BreadcrumbsProps {
    items: BreadcrumbItem[];
    className?: string;
    style?: React.CSSProperties;
    action?: React.ReactNode;
}

export function Breadcrumbs({ items, className = "", style, action }: BreadcrumbsProps) {
    return (
        <nav className={`breadcrumbs ${className}`} style={style} aria-label="Breadcrumb">
            <ol className="breadcrumbs-list">
                {items.map((item, index) => {
                    const isLast = index === items.length - 1;
                    return (
                        <li key={item.id} className="breadcrumbs-item">
                            {item.onClick ? (
                                <button
                                    type="button"
                                    className={`breadcrumbs-link ${isLast ? "breadcrumbs-link--active" : ""}`}
                                    onClick={item.onClick}
                                    aria-current={isLast ? "page" : undefined}
                                >
                                    {item.label}
                                </button>
                            ) : (
                                <span className={`breadcrumbs-text ${isLast ? "breadcrumbs-text--active" : ""}`} aria-current={isLast ? "page" : undefined}>
                                    {item.label}
                                </span>
                            )}
                            {!isLast && (
                                <span className="material-symbols-rounded breadcrumbs-separator" aria-hidden="true">
                                    chevron_right
                                </span>
                            )}
                        </li>
                    );
                })}
            </ol>
            {action && <div className="breadcrumbs-action">{action}</div>}
        </nav>
    );
}
