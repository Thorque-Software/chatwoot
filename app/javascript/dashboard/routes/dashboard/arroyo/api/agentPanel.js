/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ArroyoAgentPanelAPI extends ApiClient {
  constructor() {
    super('arroyo/agent_panel', { accountScoped: true });
  }

  getReport(params) {
    return axios.get(this.url, { params });
  }

  getConversations(params) {
    return axios.get(`${this.url}/conversations`, { params });
  }

  getWindows(params) {
    return axios.get(`${this.url}/windows`, { params });
  }

  exportReport(params) {
    return axios.get(`${this.url}/export`, { params });
  }
}

export default new ArroyoAgentPanelAPI();
