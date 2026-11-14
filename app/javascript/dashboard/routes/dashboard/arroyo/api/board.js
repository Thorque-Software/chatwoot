/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Embudo unificado del panel (Api::V1::Accounts::Arroyo::BoardController)
class BoardAPI extends ApiClient {
  constructor() {
    super('arroyo/commercial/board', { accountScoped: true });
  }

  get(params) {
    return axios.get(this.url, { params });
  }

  getOpportunities(params) {
    return axios.get(`${this.url}/opportunities`, { params });
  }

  exportCsv(params) {
    return axios.get(`${this.url}/export`, { params });
  }
}

export default new BoardAPI();
