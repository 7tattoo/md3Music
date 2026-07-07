// 升级概念版VIP（需要登录，需要先领取一天VIP）
module.exports = (params, useAxios) => {
  const paramsMap = {
    kugouid: Number(params?.userid || params?.cookie?.userid || 0),
    ad_type: 1,
  };

  return useAxios({
    url: '/youth/v1/listen_song/upgrade_vip_reward',
    encryptType: 'android',
    method: 'post',
    params: paramsMap,
    cookie: params?.cookie,
  });
};
