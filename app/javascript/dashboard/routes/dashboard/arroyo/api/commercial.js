/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class CommercialAPI extends ApiClient {
  constructor() {
    super('arroyo/commercial', { accountScoped: true });
  }

  getReport(params) {
    return axios.get(`${this.url}/report`, { params });
  }

  getOpportunities(params) {
    return axios.get(`${this.url}/opportunities`, { params });
  }

  createOpportunity(data) {
    return axios.post(`${this.url}/opportunities`, data);
  }

  updateOpportunity(id, data) {
    return axios.patch(`${this.url}/opportunities/${id}`, data);
  }

  exportReport(params) {
    return axios.get(`${this.url}/export`, { params });
  }
}

export default new CommercialAPI();
