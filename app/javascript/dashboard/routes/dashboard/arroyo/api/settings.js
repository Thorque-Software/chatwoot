/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ArroyoSettingsAPI extends ApiClient {
  constructor() {
    super('arroyo/settings', { accountScoped: true });
  }

  updateConfig(config) {
    return axios.patch(this.url, { config });
  }
}

export default new ArroyoSettingsAPI();
