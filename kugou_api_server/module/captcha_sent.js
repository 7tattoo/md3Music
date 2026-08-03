// 手机验证码发送
module.exports = (params, useAxios) => {
  const dataMap = {
    businessid: 5,
    mobile: `${params?.mobile}`,
    plat: 3,
  };

  return useAxios({
    baseURL: 'http://115.29.236.96:5621',
    url: '/captcha/sent',
    method: 'POST',
    data: dataMap,
    encryptType: 'android',
    cookie: {mid: params?.cookie?.KUGOU_API_MID},
  });
};
