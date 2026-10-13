/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ArroyoPostSaleAPI extends ApiClient {
  constructor() {
    super('arroyo/post_sale', { accountScoped: true });
  }

  getFollowUps(params) {
    return axios.get(`${this.url}/follow_ups`, { params });
  }

  resolve(id, data) {
    return axios.post(`${this.url}/follow_ups/${id}/resolve`, data);
  }

  updatePurchase(reference, data) {
    return axios.patch(
      `${this.url}/purchases/${encodeURIComponent(reference)}`,
      data
    );
  }
}

export default new ArroyoPostSaleAPI();
