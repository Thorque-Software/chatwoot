/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class CommercialFollowUpsAPI extends ApiClient {
  constructor() {
    super('arroyo/commercial/follow_ups', { accountScoped: true });
  }

  getAll(params) {
    return axios.get(this.url, { params });
  }

  sendNow(data) {
    return axios.post(`${this.url}/send_now`, data);
  }

  reschedule(data) {
    return axios.patch(`${this.url}/reschedule`, data);
  }

  enroll(data) {
    return axios.post(`${this.url}/enroll`, data);
  }
}

export default new CommercialFollowUpsAPI();
