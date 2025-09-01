class ChatApiService {
  constructor() {
    // Get CSRF token for Rails requests
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
  }

  async sendQuery(query, appType = 'pioneer', chatService = null) {
    const response = await fetch('/api/ai-query', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        query: query,
        app_type: appType,
        chat_context: chatService // This will be managed on backend via session
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.error || `HTTP ${response.status}: ${response.statusText}`);
    }

    return await response.json();
  }

  async resetChat() {
    const response = await fetch('/api/reset-chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error(`Failed to reset chat: ${response.statusText}`);
    }

    return await response.json();
  }

  async checkChatStatus() {
    const response = await fetch('/api/chat-status', {
      headers: {
        'X-CSRF-Token': this.csrfToken,
        'Accept': 'application/json'
      }
    });
    return await response.json();
  }

  // Helper method to get current app type from the page
  getCurrentAppType() {
    const appTypeSelect = document.querySelector('#appType');
    return appTypeSelect?.value || 'pioneer';
  }

  // Helper to get current timeframe if needed for context
  getCurrentTimeframe() {
    const timeframeSelect = document.querySelector('#timeframe');
    return timeframeSelect?.value || '24h';
  }
}

// Create singleton instance
const chatApiService = new ChatApiService();

export default chatApiService;
