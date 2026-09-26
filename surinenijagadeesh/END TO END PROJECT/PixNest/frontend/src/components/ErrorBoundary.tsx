import { Component, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
}

// Top-level error boundary: a render-time exception shows a recoverable message
// instead of white-screening the whole app.
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <div className="mx-auto max-w-md px-4 py-16 text-center">
          <p className="text-sm font-medium text-neutral-800">
            Something went wrong.
          </p>
          <p className="mt-1 text-xs text-neutral-500">
            {this.state.error.message}
          </p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-4 rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
