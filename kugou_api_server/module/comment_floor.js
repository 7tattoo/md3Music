// 楼层评论
//
// 走 replylist（按时间倒序，新的在前）而非 hot_replylist（按点赞降序）：
// 楼中楼是对话，需要时间顺序；且 hot_replylist 的分页不可靠——同一 id 会在
// 多个非相邻页重复出现（实测最多 5 次），并且漏掉部分回复，返回的 id 集合还
// 随 pagesize 变化（183 条的楼层在 pagesize=30 时只能取到 155 条唯一回复）。
// replylist 分页无重叠无遗漏，且跨页保持时间倒序。
const songCode = 'fc4be23b4e972707f36b8a828a93ba8a';
const playlistCode = 'ca53b96fe5a1d9c22d71c8f522ef7c4f';
const albumCode = '94f1792ced1df89aa68a7939eaf2efca';

const isNonEmpty = (value) => {
  if (value == null) return false;
  const text = `${value}`.trim();
  return text !== '' && text !== 'null' && text !== 'undefined';
};

const resolveFloorCommentRequestConfig = (params = {}) => {
  const resourceType = `${params.resource_type || params.resourceType || ''}`.toLowerCase();
  const code = isNonEmpty(params.code)
    ? `${params.code}`
    : resourceType === 'playlist'
        ? playlistCode
        : resourceType === 'album'
            ? albumCode
            : songCode;

  const useServiceEndpoint =
    resourceType === 'playlist' ||
    resourceType === 'album' ||
    code === playlistCode ||
    code === albumCode;

  const paramsMap = {
    childrenid: params.special_id,
    need_show_image: 1,
    p: params.page || 1,
    pagesize: params.pagesize || 30,
    show_classify: params.show_classify ?? 1,
    show_hotword_list: params.show_hotword_list ?? 1,
    code,
    tid: params.tid,
  };

  if (isNonEmpty(params.mixsongid)) {
    paramsMap.mixsongid = params.mixsongid;
  }

  return {
    url: useServiceEndpoint
      ? '/m.comment.service/v1/replylist'
      : '/mcomment/v1/replylist',
    encryptType: 'android',
    method: 'POST',
    params: paramsMap,
    cookie: params?.cookie || {},
  };
};

const commentFloor = (params, useAxios) => {
  return useAxios(resolveFloorCommentRequestConfig(params));
};

module.exports = commentFloor;
module.exports.resolveFloorCommentRequestConfig = resolveFloorCommentRequestConfig;
