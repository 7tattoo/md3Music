// 领取一天VIP（需要登录）
module.exports = (params, useAxios) => {
  const receiveDay = params?.body?.receive_day || params?.receive_day;
  return useAxios({
    url: '/youth/v1/recharge/receive_vip_listen_song',
    encryptType: 'android',
    method: 'post',
    params: { source_id: 90139, receive_day: receiveDay },
    data: { receive_day: receiveDay },
    cookie: params?.cookie,
  });
};
