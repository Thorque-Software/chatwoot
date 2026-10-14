/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ArroyoSocialCommentsAPI extends ApiClient {
  constructor() {
    super('arroyo/social_comments', { accountScoped: true });
  }

  channels() {
    return axios.get(`${this.url}/channels`);
  }

  createChannel(channel) {
    return axios.post(`${this.url}/channels`, { channel });
  }

  updateChannel(id, channel) {
    return axios.patch(`${this.url}/channels/${id}`, { channel });
  }

  comments(params) {
    return axios.get(`${this.url}/comments`, { params });
  }

  context(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}`);
  }

  retry(id) {
    return axios.post(`${this.url}/replies/${id}/retry`);
  }
}

export default new ArroyoSocialCommentsAPI();
