Rails.application.routes.draw do
  # Root route - serves the React app
  root "dashboard#index"

  # Simple API routes
  get "api/dashboard", to: "dashboard#api_data"
  post "api/ai-query", to: "dashboard#ai_query"   # Existing AI Query endpoint
  post "api/reset-chat", to: "dashboard#reset_chat"  # NEW: Reset chat context
  get "api/chat-status", to: "dashboard#chat_status"
  get "api/health", to: "dashboard#health_check"

  # Catch all route for React Router (if needed later)
  get "*path", to: "dashboard#index", constraints: ->(request) do
    !request.xhr? && request.format.html?
  end
end
