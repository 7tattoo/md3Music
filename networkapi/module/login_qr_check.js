const { srcappid, appid } = require('../util');

module.exports = (params, useAxios) => {
  return new Promise((resolve, reject) => {
    useAxios({
      baseURL: 'https://login-user.kugou.com',
      url: '/v2/get_userinfo_qrcode',
      method: 'GET',
      params: { plat: 4, appid, srcappid, qrcode: params?.key },
      encryptType: 'web',
      cookie: params?.cookie || {},
    }).then(resp => {
      const status = resp.body?.data?.status;
      console.log(`[QR_CHECK] status=${status} hasToken=${!!resp.body?.data?.token}`);
      if (status == 4) {
        resp.cookie.push(`token=${resp.body?.data?.token}`);
        resp.cookie.push(`userid=${resp.body?.data?.userid}`);
        if (!resp.body.token) resp.body.token = resp.body.data.token;
        if (!resp.body.userid) resp.body.userid = resp.body.data.userid;
        if (resp.body?.data?.vip_token) {
          resp.cookie.push(`vip_token=${resp.body.data.vip_token}`);
          if (!resp.body.vip_token) resp.body.vip_token = resp.body.data.vip_token;
        }
        if (resp.body?.data?.vip_type != null) {
          resp.cookie.push(`vip_type=${resp.body.data.vip_type}`);
          if (resp.body.vip_type == null) resp.body.vip_type = resp.body.data.vip_type;
        }
      }
      resolve(resp);
    }).catch(e => reject(e));
  });
};
