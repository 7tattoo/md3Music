const { srcappid, appid } = require('../util');

// 二维�?key 生成接口
module.exports = (params, useAxios) => {
  return useAxios({
    baseURL: 'http://115.29.236.96:5621',
    url: '/login/qr/key',
    method: 'GET',
    params: {
      appid: params?.type === 'web' ? 1014 : 1001,
      type: 1,
      plat: 4,
      qrcode_txt: `https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=${appid}&`,
      srcappid,
    },
    encryptType: 'web',
    cookie: params?.cookie || {},
  });
};
